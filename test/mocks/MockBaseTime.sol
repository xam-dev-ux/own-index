// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Stand-in for the BaseTime predeploy, etched at its reserved address in tests.
/// Anvil does not produce BaseTime metadata, so this is the only local simulation.
contract MockBaseTime {
    uint16 public timestampMillisPart_;
    bool public overrideMs;
    uint256 public msValue;

    function setMillisPart(uint16 v) external {
        timestampMillisPart_ = v;
    }

    /// @dev Pin `timestampMs()` to an arbitrary value instead of deriving it.
    function setTimestampMs(uint256 v) external {
        overrideMs = true;
        msValue = v;
    }

    function timestampMillisPart() external view returns (uint16) {
        return timestampMillisPart_;
    }

    function timestampMs() external view returns (uint256) {
        if (overrideMs) return msValue;
        return block.timestamp * 1000 + timestampMillisPart_;
    }
}

/// @dev Matches the pre-activation state: proxy runtime present, implementation unset, calls revert.
contract RevertingBaseTime {
    fallback() external {
        revert("implementation not set");
    }
}

/// @dev Returns data too short to be a uint.
contract ShortReturnBaseTime {
    fallback() external {
        assembly {
            mstore(0, 1)
            return(0, 1)
        }
    }
}
