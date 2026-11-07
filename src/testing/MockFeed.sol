// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice TEST ONLY. Deployed on Sepolia for the rehearsal; has no meaning anywhere else.
/// A feed that can be put into every state SessionOracle must classify: fresh, old, future-dated,
/// absurd price, zero timestamp, reverting, short return data, wrong decimals.
contract MockFeed {
    address public immutable owner;
    int256 public answer;
    uint256 public updatedAt;
    uint8 public decimals = 8;
    bool public reverts;
    bool public shortReturn;

    error NotOwner();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function set(int256 answer_, uint256 updatedAt_) external onlyOwner {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function setReverts(bool v) external onlyOwner {
        reverts = v;
    }

    function setShortReturn(bool v) external onlyOwner {
        shortReturn = v;
    }

    function setDecimals(uint8 d) external onlyOwner {
        decimals = d;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        require(!reverts, "feed down");
        if (shortReturn) {
            assembly {
                return(0, 32)
            }
        }
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

/// @notice TEST ONLY. Stands in for the Coinbase OracleRegistry pause flag.
contract MockRegistry {
    address public immutable owner;
    mapping(address => bool) public pausedToken;

    constructor() {
        owner = msg.sender;
    }

    function setPaused(address token, bool p) external {
        require(msg.sender == owner, "owner");
        pausedToken[token] = p;
    }

    function getOracleParams(address token) external view returns (uint256, bool) {
        return (1e18, pausedToken[token]);
    }
}

/// @notice TEST ONLY. Any contract with code satisfies configureToken's token check.
contract MockStock {
    string public symbol;

    constructor(string memory s) {
        symbol = s;
    }
}
