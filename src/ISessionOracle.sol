// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISessionOracle
/// @notice Types and read interface for session-aware reference data on tokenized equities.
/// @dev NOT a liquidation oracle. Reference data only. Interface draft: shape of `Mark` under review.
interface ISessionOracle {
    /// @notice Verdict. Say whether the price may be used for a decision.
    enum Session {
        FRESH,             // inside the feed session and the print is recent enough
        CLOSED,            // the market is legitimately closed; the held price is the last print
        STALE_IN_SESSION,  // the feed should be updating and is not
        PAUSED,            // corporate-action pause flagged by the registry
        UNKNOWN            // cannot be classified; do not infer anything
    }

    /// @notice Why the verdict is what it is. A consumer must be able to tell a closed market from a failure
    /// without guessing. Every non-FRESH verdict has exactly one of these.
    enum Cause {
        NONE,                 // FRESH
        WEEKEND,              // CLOSED
        HOLIDAY,              // CLOSED, full-day closure from the calendar
        EARLY_CLOSE,          // CLOSED, after the shortened close of a half day
        OUTSIDE_FEED_HOURS,   // CLOSED, between daily feed sessions
        FEED_NOT_UPDATING,    // STALE_IN_SESSION
        REGISTRY_PAUSED,      // PAUSED
        FEED_INVALID,         // UNKNOWN: answer <= 0, updatedAt == 0, incomplete round, or the call reverted
        CALENDAR_NOT_LOADED,  // UNKNOWN: the date is beyond the confirmed calendar horizon
        NOT_CONFIGURED        // UNKNOWN: token not registered
    }

    /// @notice Whether a primary/secondary comparison was possible. `divergenceBps` is meaningful only for COMPARED.
    enum DivergenceStatus {
        NO_SECONDARY,         // no secondary feed configured
        NOT_COMPARABLE_CLOSED,// market closed: no comparison is expected. Not an anomaly.
        NOT_COMPARABLE_FAULT, // one side is not FRESH while the market is open
        NOT_COMPARABLE_NEW,   // a feed registered too recently to have history
        PRINTS_TOO_FAR_APART, // both fresh but printed more than the comparison window apart: lag, not disagreement
        COMPARED
    }

    struct Mark {
        // --- primary feed, always. Never replaced by the secondary. ---
        int256 price;                 // 8 decimals, Chainlink Total Return Value. Multiplier already included.
        Session session;
        Cause cause;
        uint32 stalenessSecs;         // block.timestamp - updatedAt, saturating
        uint16 confidenceBps;         // 10000 when FRESH, degrading with staleness
        uint64 timestampMs;           // BaseTime when active, else block.timestamp * 1000
        // --- secondary feed, reported alongside, never substituted ---
        DivergenceStatus divergenceStatus;
        int256 divergenceBps;         // (secondary - primary) / primary, signed. Valid only if COMPARED.
        int256 secondaryPrice;        // 0 if none
        uint32 printLagSecs;          // |updatedAt(primary) - updatedAt(secondary)|; 0 if none
    }

    function markOf(address token) external view returns (Mark memory);
    function isFresh(address token) external view returns (bool);
    function marksOf(address[] calldata tokens) external view returns (Mark[] memory);
}
