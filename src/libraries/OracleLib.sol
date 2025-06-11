// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePriceFeed(
        uint80 roundID, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );

    uint256 private constant TIMEOUT = 3 hours;

    function stalePriceCheck(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        // If the last updated timestamp is 0, it means the price feed has never been updated.
        priceFeed.latestRoundData();
        (uint80 roundID, int256 price, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();
        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (updatedAt == 0 || secondsSinceLastUpdate > TIMEOUT) {
            revert OracleLib__StalePriceFeed(roundID, price, startedAt, updatedAt, answeredInRound);
        }
        return (roundID, price, startedAt, updatedAt, answeredInRound);
    }
}
