// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockAggregator {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public decimals = 8;
    bool public reverts;
    bool public shortReturn;

    function set(int256 a, uint256 u) external {
        answer = a;
        updatedAt = u;
    }
    function setReverts(bool r) external { reverts = r; }
    function setShort(bool s) external { shortReturn = s; }
    function setDecimals(uint8 d) external { decimals = d; }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!reverts, "feed down");
        if (shortReturn) {
            assembly { return(0, 32) }
        }
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockRegistry {
    bool public paused;
    function setPaused(bool p) external { paused = p; }
    function getOracleParams(address) external view returns (uint256, bool) { return (1e18, paused); }
}

contract MockToken { function x() external pure returns (uint256) { return 1; } }
