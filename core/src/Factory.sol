// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import "v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {InterestModel} from "./InterestModel.sol";
import {Kitty} from "./Kitty.sol";
import {MarginAccount} from "./MarginAccount.sol";
import {MarginAccountFactory} from "./MarginAccountFactory.sol";

contract Factory {
    event CreateMarket(IUniswapV3Pool indexed pool, Kitty indexed kitty0, Kitty indexed kitty1);

    event CreateMarginAccount(IUniswapV3Pool indexed pool, MarginAccount indexed account, address indexed owner);

    struct Market {
        Kitty kitty0;
        Kitty kitty1;
    }

    InterestModel public immutable INTEREST_MODEL;

    MarginAccountFactory public immutable MARGIN_ACCOUNT_FACTORY;

    mapping(IUniswapV3Pool => Market) public getMarket;

    mapping(address => bool) public isMarginAccount;

    mapping(Kitty => mapping(address => bool)) public isMarginAccountAllowed;

    constructor(InterestModel _interestModel, MarginAccountFactory _marginAccountFactory) {
        INTEREST_MODEL = _interestModel;
        MARGIN_ACCOUNT_FACTORY = _marginAccountFactory;
    }

    function createMarket(IUniswapV3Pool _pool) external {
        ERC20 asset0 = ERC20(_pool.token0());
        ERC20 asset1 = ERC20(_pool.token1());

        // TODO this implies that lending pairs are fee-tier specific. does it make sense to combine fee tiers?
        //      if so, margin account Uniswap liquidity readers will have to change.
        Kitty kitty0 = new Kitty{salt: keccak256(abi.encode(_pool))}(asset0, INTEREST_MODEL, address(this));
        Kitty kitty1 = new Kitty{salt: keccak256(abi.encode(_pool))}(asset1, INTEREST_MODEL, address(this));

        getMarket[_pool] = Market(kitty0, kitty1);
        emit CreateMarket(_pool, kitty0, kitty1);
    }

    function createMarginAccount(IUniswapV3Pool _pool, address _owner) external returns (MarginAccount account) {
        Market memory market = getMarket[_pool];
        account = MARGIN_ACCOUNT_FACTORY.createMarginAccount(_pool, market.kitty0, market.kitty1, _owner);

        isMarginAccount[address(account)] = true;
        // TODO ensure this constrains things properly, i.e. a WETH/USDC margin account and a WETH/WBTC margin account shouldn't be able to borrow from the same WBTC kitty
        isMarginAccountAllowed[market.kitty0][address(account)] = true;
        isMarginAccountAllowed[market.kitty1][address(account)] = true;
        emit CreateMarginAccount(_pool, account, _owner);

        // TODO could append account address to a (address => address[]) mapping to make it easier to fetch all accounts for a given user.
    }
}