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

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * Collateral: Exogenous
 * Minting (Stability Mechanism): Decentralized (Algorithmic)
 * Value (Relative Stability): Anchored (Pegged to USD)
 * Collateral Type: Crypto
 *
 * This is the contract meant to be owned by DSCEngine. It is a ERC20 token that can be minted and burned by the
DSCEngine smart contract.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__InsufficientBalance(uint256 available, uint256 required);
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__NotZeroAddress();

    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        _mint(to, amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        if (_amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        uint256 balance = balanceOf(msg.sender);
        if (balance < _amount) {
            revert DecentralizedStableCoin__InsufficientBalance(balance, _amount);
        }
        super.burn(_amount);
    }
}
