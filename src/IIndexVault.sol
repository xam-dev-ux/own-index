// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISessionOracle} from "./ISessionOracle.sol";

/// @title IIndexVault
/// @notice Interface draft for a self-custodial, user-weighted index vault. Review the refusal policy first.
/// @dev Owned by one user. No share token, no fees, no discretion beyond the owner's own parameters.
/// The vault has no knowledge of Builder Codes: attribution is a calldata suffix added by the client.
interface IIndexVault {
    // ------------------------------------------------------------ data
    struct Component {
        address token;
        uint16 targetWeightBps; // sums to 10_000
    }

    /// @dev No `requireFreshFeeds` and no `maxStaleGapBps`: the vault never trades against a non-FRESH mark.
    struct Rules {
        uint16 driftThresholdBps;
        uint32 minRebalanceInterval; // seconds
        uint16 maxSlippageBps;       // per swap, against the oracle price. Hard cap 500.
    }

    /// @notice What is being attempted. Only TRADE actions consult the oracle.
    enum Action { REBALANCE, DEPOSIT_WITH_SWAPS }

    /// @notice Why a trade was refused. Mirrors the oracle one to one.
    enum RefusalKind {
        NONE,
        MARKET_CLOSED,             // Mark.session == CLOSED. Cause says weekend, holiday or early close.
        AWAITING_FIRST_PRINT,      // stale and possibly wrong after a reopen. Dry refusal.
        FEED_FAULT,                // STALE_IN_SESSION (not awaiting) or UNKNOWN. Cause says which.
        CORPORATE_ACTION_PAUSE,    // Mark.session == PAUSED
        MULTIPLIER_CHANGE_IMMINENT,// token.effectiveAt() inside the window
        NO_DRIFT,
        TOO_SOON,
        SLIPPAGE_EXCEEDED,         // post-trade: executed value fell outside maxSlippageBps. Recorded by tryRebalance only.
        IMPACT_CAP_EXCEEDED        // post-trade: a component moved by more than its immutable cap. Recorded by tryRebalance only.
    }

    struct Refusal {
        RefusalKind kind;
        address token;                    // offending component; address(0) for NO_DRIFT / TOO_SOON
        ISessionOracle.Cause cause;       // oracle cause; NONE where not applicable
    }

    // ------------------------------------------------------------ errors (revert path)
    error NotOwner();
    error WeightsMustSumTo10000();
    error MarketClosed(address token, ISessionOracle.Cause cause);
    error AwaitingFirstPrint(address token);
    error FeedFault(address token, ISessionOracle.Cause cause);
    error CorporateActionPause(address token);
    error MultiplierChangeImminent(address token, uint256 effectiveAt);
    error NoDriftDetected();
    error RebalanceTooSoon(uint64 nextEligibleAt);
    /// @dev Aggregate over the whole batch: `traded` is the value bought (oracle prices), `loss` the value lost.
    error SlippageExceeded(uint256 traded, uint256 loss, uint256 maxLossAllowed);
    error ImpactCapExceeded(address token, uint256 movedValue, uint256 cap);
    error SlippageCapExceeded(uint16 requested); // rules.maxSlippageBps > 500
    error InvalidRules();
    error BadComponents();
    error TokenNotAllowed(address token);
    error SwapFailed(uint256 index);
    error NotSelf();
    error Reentrancy();
    error AlreadyInitialized();
    error LengthMismatch();

    // ------------------------------------------------------------ events
    event Deposited(address indexed asset, uint256 amount);
    event Withdrawn(address indexed asset, uint256 amount, address indexed to);
    event Rebalanced(uint256 indexed id, address indexed caller, uint64 timestampMs);
    /// @dev One event per offending component. Emitted only by the recording path (`tryRebalance`).
    event RebalanceRefused(
        uint256 indexed refusalId, RefusalKind kind, address indexed token, ISessionOracle.Cause cause, uint64 timestampMs
    );
    event RulesUpdated();
    event ComponentsUpdated();

    event OwnerSet(address indexed owner);

    // ------------------------------------------------------------ owner actions
    /// @notice Atomic. If any component refuses, the whole call reverts with that component's error.
    /// Never partially executes the basket.
    function rebalance(bytes[] calldata swapCalldata) external;

    /// @notice Same checks and same atomicity, but a refusal does not revert: it stores a refusal count,
    /// emits `RebalanceRefused` for every offending component and returns false without trading.
    /// This is the path that leaves an onchain record, since a reverted call leaves no logs.
    function tryRebalance(bytes[] calldata swapCalldata) external returns (bool executed);

    /// @notice Atomic and gated exactly like `rebalance`, because swapping USDC into components is trading.
    function deposit(uint256 usdcAmount, bytes[] calldata swapCalldata) external;

    /// @notice Never consults the oracle, a router or a feed.
    function depositInKind(address[] calldata tokens, uint256[] calldata amounts) external;
    function withdraw(address asset, uint256 amount, address to) external;
    /// @notice Unconditional escape hatch. No oracle, no router, no freshness, no calendar.
    function withdrawAllInKind(address to) external;

    function setComponents(Component[] calldata components) external;
    function setRules(Rules calldata rules) external;

    // ------------------------------------------------------------ views
    function currentWeights() external view returns (uint16[] memory);
    /// @notice Valuation uses feed answers directly. They are Total Return Values and already include
    /// the multiplier: never multiply again.
    function totalValue() external view returns (uint256 value, bool allFresh);
    function scaledHoldings() external view returns (uint256[] memory); // display only, never used in valuation
    /// @notice Structured, so a UI can render it without parsing strings.
    function rebalanceStatus() external view returns (
        bool possible, Refusal[] memory refusals, uint64 nextEligibleAt, uint16 maxDriftBps
    );
    function refusalCount() external view returns (uint256);
    function rebalanceCount() external view returns (uint256);
}
