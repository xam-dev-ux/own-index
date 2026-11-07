// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBaseTime {
    function timestampMillisPart() external view returns (uint16);
    function timestampMs() external view returns (uint256);
}

/// @notice Safe access to Denim's BaseTime predeploy.
/// @dev On chains where Denim has not activated, the reserved address holds the
/// canonical proxy runtime but its implementation slot is unset, so calls
/// revert. Every function here degrades to whole-second behaviour instead.
/// Resolution is 200ms: the millisecond part takes only the values
/// 0, 200, 400, 600 and 800, giving five slots per second.
library BaseTimeLib {
    address internal constant BASE_TIME = 0x4200000000000000000000000000000000000030;

    /// @notice The only valid millisecond parts are multiples of this.
    uint16 internal constant SLOT_INTERVAL_MS = 200;
    uint8 internal constant SLOTS_PER_SECOND = 5;

    /// @dev Reads the millisecond part. `ok` is false when the call reverts, the
    /// return data is malformed, or the value is not one of 0/200/400/600/800.
    function _read() private view returns (bool ok, uint16 part) {
        (bool success, bytes memory ret) =
            BASE_TIME.staticcall(abi.encodeCall(IBaseTime.timestampMillisPart, ()));
        if (!success || ret.length < 32) return (false, 0);
        uint256 raw = abi.decode(ret, (uint256));
        if (raw >= 1000 || raw % SLOT_INTERVAL_MS != 0) return (false, 0);
        return (true, uint16(raw));
    }

    /// @notice True when the predeploy is linked and answering with a valid value.
    function isActive() internal view returns (bool ok) {
        (ok,) = _read();
    }

    /// @notice Full millisecond timestamp (200ms resolution), or whole-second
    /// time scaled to milliseconds when the predeploy is unavailable.
    function timestampMs() internal view returns (uint256) {
        (bool ok,) = _read();
        if (ok) {
            (bool success, bytes memory ret) =
                BASE_TIME.staticcall(abi.encodeCall(IBaseTime.timestampMs, ()));
            if (success && ret.length >= 32) return abi.decode(ret, (uint256));
        }
        return block.timestamp * 1000;
    }

    /// @notice Millisecond part of the current block, or 0 pre-activation or if
    /// the predeploy returns anything other than 0/200/400/600/800.
    function millisPart() internal view returns (uint16 part) {
        (, part) = _read();
    }

    /// @notice Which of the five 200ms slots within the current second this
    /// block occupies, 0 through 4. Always 0 when the predeploy is unavailable.
    function slotIndex() internal view returns (uint8) {
        return uint8(millisPart() / SLOT_INTERVAL_MS);
    }
}
