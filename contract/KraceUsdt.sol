// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract KraceUsdt is ERC20, ERC20Burnable {
    
    constructor() ERC20("KraceUsdt", "USDT") {
        _mint(msg.sender, type(uint256).max);
    }

    function decimals() public pure override returns (uint8) {
		return 6;
	}
}