// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract ERC1155Example is ERC1155 {
    uint public currentNftId;

    constructor() ERC1155("https://randomuri.com"){
        currentNftId = 1;
    }

    function mint(uint _amount) external {
        uint[] memory ids = new uint[](_amount);
        uint[] memory amounts = new uint[](_amount);

        for (uint i = 0; i < _amount; i++) {
            ids[i] = currentNftId;
            amounts[i] = 5;

            currentNftId++;
        }

        _mintBatch(msg.sender, ids, amounts, "");
    }
}