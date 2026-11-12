// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice TEST ONLY. 6-decimal stablecoin stand-in (like USDC on Polygon).
contract MockStablecoin is ERC20 {
    constructor() ERC20("Mock USD", "mUSD") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
