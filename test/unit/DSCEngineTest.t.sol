// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDsc} from "../../script/DeployDsc.s.sol";
import {console} from "forge-std/console.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDsc public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dscEngine;
    HelperConfig public config;

    address public ethUsdPriceFeed;
    address public weth;
    address public wbtcUsdPriceFeed;
    address public wbtc;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public USER = makeAddr("user");

    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;

    function setUp() public {
        deployer = new DeployDsc();
        (dsc, dscEngine, config) = deployer.run();
        (ethUsdPriceFeed, weth, wbtcUsdPriceFeed, wbtc,) = config.activeNetworkConfig();
    }

    function testRevertIfTokenLengthMismatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(wbtcUsdPriceFeed);
        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPriceFeedLengthMustMatch.selector);
        DSCEngine newDscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testGetUsdValue() public {
        uint256 amount = 10 ether; // 10 ETH
        uint256 expectedUsdValue = 20000e18; // Assuming ETH price is $2000
        uint256 usdValue = dscEngine.getUsdValue(weth, amount);
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        assertEq(usdValue, expectedUsdValue, "USD value should match expected value");
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmount = 20000e18; // $20000
        uint256 expectedTokenAmount = 10 ether; // Assuming ETH price is $2000
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(tokenAmount, expectedTokenAmount, "Token amount should match expected value");
    }

    function testIfTokenNotAllowed() public {
        address fakeToken = address(new ERC20Mock("Fake Token", "FAKE", USER, 1000 ether));
        vm.startPrank(USER);
        ERC20Mock(fakeToken).approve(USER, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__TokenNotAllowed.selector, fakeToken));
        dscEngine.depositCollateral(fakeToken, 100 ether);
        vm.stopPrank();
    }

    function testIfCollateralIsZero() public depositCollateralSetup {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), 10 ether);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    modifier depositCollateralSetup() {
        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_COLLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testGetAccountInformation() public depositCollateralSetup {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        uint256 expectedDscMinted = 0; // No DSC minted yet
        assertEq(AMOUNT_COLLATERAL, expectedDepositAmount, "Collateral value should match expected value");
        assertEq(totalDscMinted, expectedDscMinted, "Total Dsc should match expected value");
    }
}
