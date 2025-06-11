//SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {console} from "forge-std/console.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test {
    DeployDsc public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;
    Handler public handler;

    address public ethUsdPriceFeed;
    address public weth;
    address public wbtcUsdPriceFeed;
    address public wbtc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, weth, wbtcUsdPriceFeed, wbtc,) = config.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_DSCIsAlwaysBackedByCollateral() public view {
        uint256 totalDscSupply = dsc.totalSupply();
        uint256 totalWethBalance = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcBalance = ERC20Mock(wbtc).balanceOf(address(dscEngine));
        uint256 wethPrice = dscEngine.getUsdValue(weth, totalWethBalance);
        uint256 wbtcPrice = dscEngine.getUsdValue(wbtc, totalWbtcBalance);
        uint256 totalCollateralValue = wethPrice + wbtcPrice;
        console.log("Total DSC Supply:", totalDscSupply);
        console.log("Total Collateral Value in USD:", totalCollateralValue);
        console.log("Time Mint Called:", handler.timeMintIsCalled());
        // The total collateral value should always be greater than or equal to the total supply of DSC
        assert(totalCollateralValue >= totalDscSupply);
    }

    function invariant_GettersShouldNotRevert() public view {
        dscEngine.getCollateralTokens();
    }
}
