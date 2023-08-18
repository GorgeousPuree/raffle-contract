// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract ERC721Example is ERC721 {
    uint public currentNftId;

    constructor() ERC721("ERC721 example contract", "ERC721EXAMPLE"){
        currentNftId = 1;
    }

    function mint(uint _amount) external {
        for (uint i = 0; i < _amount; i++) {
            _mint(msg.sender, currentNftId);
            currentNftId++;
        }
    }
}