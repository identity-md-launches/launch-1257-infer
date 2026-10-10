// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Infer (INFER)
/// @notice A fixed supply ERC-20 with 18 decimals, minted entirely to its deployer.
contract InferToken is ERC20 {
    /// @notice One billion INFER, expressed in the token's smallest units.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev The immediate creator receives the supply. On launch this is the factory.
    /// No minting, burning, administration, or initialization entry point is exposed.
    constructor() ERC20("Infer", "INFER") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
