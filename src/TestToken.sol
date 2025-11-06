// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TestToken
 * @notice A simple ERC20 test token with public mint function
 * @dev This token is intended for testing purposes on Ethereum Sepolia testnet.
 *      Anyone can mint tokens freely - there is no access control.
 */
contract TestToken is ERC20 {
  /**
   * @notice Initializes the token with name "Test Token" and symbol "TEST"
   */
  constructor() ERC20("Test Token", "TEST2") { }

  /**
   * @notice Mints new tokens to the specified address
   * @param to Address to receive the minted tokens
   * @param amount Amount of tokens to mint (in wei, 18 decimals)
   * @dev This function is public and can be called by anyone.
   *      The zero address check is handled by OpenZeppelin's _mint function.
   */
  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}