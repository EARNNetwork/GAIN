// SPDX-License-Identifier: MIT

/* This is a simple OpenZeppelin ERC20 token used as Dai for testing purposes*/

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GAINTESTDAIv3 is ERC20, Ownable {
    constructor() ERC20("Daitestv3", "DAItv3") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}