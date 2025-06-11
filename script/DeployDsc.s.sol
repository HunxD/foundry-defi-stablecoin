// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDsc is Script {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    address[] tokenAddress;
    address[] priceFeedAddress;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address wethUsdPriceFeed, address weth, address wbtcUsdPriceFeed, address wbtc, uint256 deployerKey) =
            config.activeNetworkConfig();
        tokenAddress = [weth, wbtc];
        priceFeedAddress = [wethUsdPriceFeed, wbtcUsdPriceFeed];

        vm.startBroadcast(deployerKey);
        dsc = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddress, priceFeedAddress, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();
        return (dsc, dscEngine, config);
    }
}
