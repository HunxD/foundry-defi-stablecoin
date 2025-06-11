// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
// import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/tests/MockV3Aggregator.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetWorkConfig {
        address wethUsdPriceFeed;
        address weth;
        address wbtcUsdPriceFeed;
        address wbtc;
        uint256 deployerKey;
    }

    uint256 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8; // 2000 USD
    int256 public constant BTC_USD_PRICE = 10000e8; // 10000 USD

    NetWorkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            // Sepolia
            activeNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 31337) {
            // Anvil
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        } else {
            revert("Unsupported network");
        }
    }

    function getSepoliaEthConfig() public returns (NetWorkConfig memory) {
        activeNetworkConfig = NetWorkConfig({
            wethUsdPriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            wbtcUsdPriceFeed: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            wbtc: 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
            deployerKey: vm.envUint("SEPOLIA_PRIVATE_KEY")
        });
        return activeNetworkConfig;
    }

    function getOrCreateAnvilEthConfig() public returns (NetWorkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(8, ETH_USD_PRICE);
        MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(8, BTC_USD_PRICE);
        ERC20Mock weth = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 1000e8);
        ERC20Mock wbtc = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();
        return NetWorkConfig({
            wethUsdPriceFeed: address(wethUsdPriceFeed),
            weth: address(weth),
            wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
            wbtc: address(wbtc),
            deployerKey: vm.envUint("ANVIL_PRIVATE_KEY")
        });
    }
}
