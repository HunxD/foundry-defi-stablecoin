// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine is ReentrancyGuard {
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__NotZeroAddress();
    error DSCEngine__TokenAndPriceFeedLengthMustMatch();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__BrokenHealthFactor(uint256 userHealthFactor, uint256 minHealthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% liquidation threshold
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // 1.0 in 18 decimals
    uint256 private constant LIQUIDATION_BONUS = 10; //10% liquidation bonus
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposits;
    mapping(address user => uint256 amountDscMinted) private s_dscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(address indexed user, address indexed tokenCollateralAddress, uint256 amountCollateral);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed(token);
        }

        _;
    }

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        //USD Price Feed
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAndPriceFeedLengthMustMatch();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_priceFeeds[tokenAddress[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddress[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /**
     * @param tokenCollateralAdress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAdress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAdress)
        nonReentrant
    {
        s_collateralDeposits[msg.sender][tokenCollateralAdress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAdress, amountCollateral);
        bool success = IERC20(tokenCollateralAdress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Mints new DSC tokens for the user
     * @param amountDscToMint The amount of DSC to mint for the user
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        _revertIfHealthFactorIsBroken(msg.sender);
        s_dscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }
    /**
     * @notice Deposits collateral and mints new DSC tokens for the user
     * @param tokenCollateralAdress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDsc The amount of DSC to mint
     */

    function depositCollateralAndMintDsc(address tokenCollateralAdress, uint256 amountCollateral, uint256 amountDsc)
        external
        isAllowedToken(tokenCollateralAdress)
        moreThanZero(amountCollateral)
        moreThanZero(amountDsc)
        nonReentrant
    {
        depositCollateral(tokenCollateralAdress, amountCollateral);
        s_dscMinted[msg.sender] += amountDsc;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDsc);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice Redeems collateral for DSC tokens and burns the specified amount of DSC tokens.
     * @param tokenCollateralAdress The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC tokens to burn
     */
    function redeemCollateralForDsc(address tokenCollateralAdress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        moreThanZero(amountDscToBurn)
        nonReentrant
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAdress, amountCollateral); //already checked health factor
    }

    function redeemCollateral(address tokenCollateralAdress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAdress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     *
     * @param amount The amount of DSC to burn
     * @notice Burns the specified amount of DSC tokens from the user's balance.
     * @dev This function is used to reduce the user's DSC supply, which can be useful for managing their debt.
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidates a user's collateral to cover their debt.
     * @param user The address of the user whose collateral is being liquidated
     * @param collateral The address of the collateral token to liquidate
     * @param debtToCover The amount of debt to cover with the liquidation
     * @notice This function allows a liquidator to take over a user's collateral when their health factor is below the minimum threshold.
     * @notice The liquidator will receive the collateral, and the user's debt will be reduced by the specified amount.
     */
    function liquidate(address user, address collateral, uint256 debtToCover) external {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, msg.sender, user);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Retrieves the total amount of DSC minted and the total collateral value in USD for a user.
     * @param user The address of the user to retrieve information for.
     * @return totalDscMinted The total amount of DSC minted by the user.
     * @return collateralValueInUsd The total value of the user's collateral in USD.
     */
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user); // Placeholder for actual collateral value calculation
    }

    /**
     * returns the health factor of the user.
     * The health factor is a measure of the user's collateralization ratio.
     * if the health factor is less than 1, the user is undercollateralized and can be liquidated.
     * @param user The address of the user to check the health factor for
     * @return The health factor of the user, represented as a uint256.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @param totalDscMinted The total amount of DSC minted by the user
     * @param collateralValueInUsd The total value of the user's collateral in USD
     */
    function _calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        internal
        pure
        returns (uint256)
    {
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @param user The address of the user to check the health factor for
     * @notice Reverts if the user's health factor is below the minimum threshold.
     * @dev This function checks the user's health factor and reverts if it is below the minimum health factor.
     */
    function _revertIfHealthFactorIsBroken(address user) private view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BrokenHealthFactor(userHealthFactor, MIN_HEALTH_FACTOR);
        }
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAdress, uint256 amountCollateral)
        private
    {
        s_collateralDeposits[from][tokenCollateralAdress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAdress, amountCollateral);
        bool success = IERC20(tokenCollateralAdress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) internal {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }
    /**
     * @param totalDscMinted The total amount of DSC minted by the user
     * @param collateralValueInUsd The total value of the user's collateral in USD
     */

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    /**
     * @param user The address of the user to retrieve collateral value for
     * @return totalCollateralValue The total value of the user's collateral in USD.
     * @notice This function calculates the total value of all collateral tokens deposited by the user in USD.
     */
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposits[user][token];
            totalCollateralValue += getUsdValue(token, amount);
        }
        return totalCollateralValue;
    }

    /**
     * @notice Retrieves the USD value of a specific token amount.
     * @param token The address of the token to get the USD value for
     * @param amount The amount of the token to convert to USD
     */
    function getUsdValue(address token, uint256 amount) public view isAllowedToken(token) returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();
        return amount * (uint256(price) * ADDITIONAL_FEED_PRECISION) / PRECISION;
    }

    /**
     * @param token The address of the token to convert from
     * @param usdAmount The amount of USD to convert to tokens
     */
    function getTokenAmountFromUsd(address token, uint256 usdAmount)
        public
        view
        isAllowedToken(token)
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheck();
        return (usdAmount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getHealthFactor() external view returns (uint256) {
        return _healthFactor(msg.sender);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        return _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralDeposits(address user, address token) external view returns (uint256) {
        return s_collateralDeposits[user][token];
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_dscMinted[user];
    }

    function getPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getDscAddress() external view returns (address) {
        return address(i_dsc);
    }
}
