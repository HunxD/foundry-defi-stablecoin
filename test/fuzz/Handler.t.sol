// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;
    address[] public usersWithCollateral;

    uint256 public timeMintIsCalled;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;
        address[] memory tokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(tokens[0]);
        wbtc = ERC20Mock(tokens[1]);
    }

    function depositCollateral(uint256 seed, uint256 amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(seed);
        address user = _getUserFromSeed(seed);
        vm.assume(user != address(0));
        amount = bound(amount, 1, 1e18);
        collateral.mint(user, amount);

        vm.startPrank(user);
        collateral.approve(address(dscEngine), MAX_DEPOSIT_SIZE);
        dscEngine.depositCollateral(address(collateral), amount);
        vm.stopPrank();
        usersWithCollateral.push(user);
    }

    function mintDsc(uint256 seed, uint256 amount) external {
        vm.assume(usersWithCollateral.length > 0);
        address user = usersWithCollateral[seed % usersWithCollateral.length];
        vm.assume(user != address(0));
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        vm.assume(collateralValueInUsd > 0);
        vm.assume(collateralValueInUsd / 2 > totalDscMinted);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        vm.assume(maxDscToMint > 0);
        amount = bound(amount, 0, uint256(maxDscToMint));
        vm.assume(amount > 0);
        vm.startPrank(user);
        dscEngine.mintDsc(amount);
        vm.stopPrank();
        timeMintIsCalled++;
    }

    function redeemCollateral(uint256 seed, uint256 amount) external {
        ERC20Mock collateral = _getCollateralFromSeed(seed);
        address user = _getUserFromSeed(seed);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(user);
        vm.assume(int256(collateralValueInUsd) - int256(totalDscMinted) * 2 > 0);
        uint256 maxAmountCollateralToRedeem = dscEngine.getTokenAmountFromUsd(
            address(collateral), uint256((int256(collateralValueInUsd) - int256(totalDscMinted) * 2))
        );
        vm.assume(user != address(0));
        // uint256 maxAmount = dscEngine.getCollateralDeposits(user, address(collateral));
        amount = bound(amount, 0, uint256(maxAmountCollateralToRedeem));
        vm.assume(amount > 0);
        vm.startPrank(user);
        dscEngine.redeemCollateral(address(collateral), amount);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock collateralToken) {
        return (collateralSeed % 2 == 0) ? weth : wbtc;
    }

    function _getUserFromSeed(uint256 seed) internal pure returns (address) {
        return address(uint160(seed));
    }
}
