// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract TokenDeployer {
    function deployToken(
        bytes memory creationCode,
        bytes memory constructorArgs
    ) external returns (address addr) {
        bytes memory fullData = abi.encodePacked(creationCode, constructorArgs);
        
        assembly {
            addr := create(0, add(fullData, 0x20), mload(fullData))
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }
}