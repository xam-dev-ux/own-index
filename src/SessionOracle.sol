// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseTimeLib} from "./BaseTimeLib.sol";
import {ISessionOracle} from "./ISessionOracle.sol";

/// @notice Session-aware reference data for tokenized equities on Base, plus a public gap ledger.
/// @dev NOT a liquidation oracle. Chainlink equity feeds run 24/5 and hold their last value while the
/// market is closed. This contract makes that state explicit and records what happens when they resume.
/// It holds no funds and has no withdraw path. All durations use timestamps, never block counts.
///
/// Time model. A feed is "open" inside a weekly window (seconds since Monday 00:00 UTC) minus closure
/// intervals the RECORDER declares (holidays, early closes). The window and the closures are the only
/// maintained state; `confirmedUntil` states how far the calendar has been checked. Past it the verdict
/// is UNKNOWN, never STALE_IN_SESSION.
contract SessionOracle is ISessionOracle {
    // ---------------------------------------------------------------- types
    enum ClosureKind { HOLIDAY, EARLY_CLOSE }

    struct TokenConfig {
        address feed;
        address secondaryFeed;       // address(0) if none
        uint32 inSessionThresholdSecs; // in open seconds; set from measured inter-print distributions
        uint64 registeredAt;
        uint64 secondaryRegisteredAt;
        bool active;
    }

    struct Closure {
        uint64 start;
        uint64 end;
        ClosureKind kind;
    }

    struct GapRecord {
        uint64 closePrintAt;      // feed updatedAt of the last print before the closure (seconds)
        int256 closePrice;
        uint64 reopenPrintAt;     // feed updatedAt of the print recorded after the reopen (seconds)
        int256 reopenPrice;
        uint64 observedAtMs;      // BaseTime time of the snapshot that recorded it (200ms); the print itself is second-resolution
        int256 gapBps;            // signed
        uint32 closureSecs;       // reopenPrintAt - closePrintAt
        uint64 observedBlock;
    }

    // ---------------------------------------------------------------- constants
    uint256 internal constant WEEK = 7 days;
    uint256 internal constant WEEK_ORIGIN = 4 days; // Monday 1970-01-05 00:00 UTC
    uint256 internal constant MAX_CLOSURES = 64;
    uint256 internal constant MAX_LOOKBACK = 14 days;
    uint256 internal constant CONFIDENCE_HORIZON = 7 days;
    uint8 internal constant FEED_DECIMALS = 8;
    int256 internal constant MAX_PRICE = 1e20; // 1e12 USD at 8 decimals; anything above is treated as invalid

    // ---------------------------------------------------------------- state
    address public immutable RECORDER;

    mapping(address => TokenConfig) public configOf;
    address[] public tokens;

    mapping(address => GapRecord[]) public gapsOf;
    mapping(address => bool) public inClosure;
    mapping(address => uint64) private closePrintAtOf;
    mapping(address => int256) private closePriceOf;

    uint32 public weekOpenOffset;   // seconds after Monday 00:00 UTC
    uint32 public weekCloseOffset;
    uint32 public heartbeatSecs;
    uint32 public heartbeatMarginSecs;
    uint32 public comparisonWindowSecs;
    uint64 public confirmedUntil;
    address public registry;        // optional Coinbase OracleRegistry, read only for the paused flag

    Closure[] private _closures;

    // ---------------------------------------------------------------- events
    event GapRecorded(
        address indexed token, int256 closePrice, int256 reopenPrice, int256 gapBps, uint32 closureSecs, uint64 observedAtMs
    );
    event ClosureDetected(address indexed token, uint64 closePrintAt, int256 lastPrice);
    event TokenConfigured(address indexed token, address feed, address secondaryFeed, uint32 thresholdSecs);
    event ClosureAdded(uint64 start, uint64 end, ClosureKind kind);
    event CalendarConfirmed(uint64 until);
    event WindowSet(uint32 openOffset, uint32 closeOffset);

    // ---------------------------------------------------------------- errors
    error NotRecorder();
    error UnknownToken(address token);
    error BadParams();
    error ClosureOrder();
    error TooManyClosures();

    modifier onlyRecorder() {
        if (msg.sender != RECORDER) revert NotRecorder();
        _;
    }

    /// @param openOffset_ seconds after Monday 00:00 UTC when the weekly feed window opens
    /// @param closeOffset_ seconds after Monday 00:00 UTC when it closes
    constructor(
        address recorder,
        uint32 openOffset_,
        uint32 closeOffset_,
        uint32 heartbeatSecs_,
        uint32 heartbeatMarginSecs_,
        uint32 comparisonWindowSecs_
    ) {
        if (recorder == address(0)) revert BadParams();
        RECORDER = recorder;
        _setWindow(openOffset_, closeOffset_);
        if (heartbeatSecs_ == 0 || comparisonWindowSecs_ == 0) revert BadParams();
        heartbeatSecs = heartbeatSecs_;
        heartbeatMarginSecs = heartbeatMarginSecs_;
        comparisonWindowSecs = comparisonWindowSecs_;
    }

    // ================================================================ reads
    function markOf(address token) public view returns (Mark memory m) {
        (m,) = _read(token);
    }

    function isFresh(address token) external view returns (bool) {
        (Mark memory m,) = _read(token);
        return m.session == Session.FRESH;
    }

    function marksOf(address[] calldata tokens_) external view returns (Mark[] memory out) {
        out = new Mark[](tokens_.length);
        for (uint256 i; i < tokens_.length; ++i) {
            (out[i],) = _read(tokens_[i]);
        }
    }

    function tokenCount() external view returns (uint256) {
        return tokens.length;
    }

    function closureCount() external view returns (uint256) {
        return _closures.length;
    }

    function closureAt(uint256 i) external view returns (Closure memory) {
        return _closures[i];
    }

    /// @notice Open seconds in [from, to], clipped to the last 14 days. Public for inspection.
    function openSecondsBetween(uint256 from, uint256 to) public view returns (uint256) {
        return _openSeconds(from, to);
    }

    /// @notice Whether the feed window is open at `t`, and if not, why.
    function openAt(uint256 t) public view returns (bool open, Cause cause) {
        return _openAt(t);
    }

    // ================================================================ gap ledger
    function snapshot(address token) public {
        (Mark memory m, uint256 updatedAt) = _read(token);
        if (m.cause == Cause.NOT_CONFIGURED) revert UnknownToken(token);

        if (!inClosure[token]) {
            if (m.session == Session.CLOSED && updatedAt != 0 && m.price > 0) {
                inClosure[token] = true;
                closePrintAtOf[token] = uint64(updatedAt);
                closePriceOf[token] = m.price;
                emit ClosureDetected(token, uint64(updatedAt), m.price);
            }
        } else if (m.session == Session.FRESH) {
            // First fresh print after the closure, as seen at observation time. The feed exposes only its
            // latest round, so if several prints landed before this call, the latest is what is recorded.
            int256 closeP = closePriceOf[token];
            int256 gap = ((m.price - closeP) * 10_000) / closeP;
            uint64 closeAt = closePrintAtOf[token];
            uint32 secs = updatedAt > closeAt ? _sat32(updatedAt - closeAt) : 0;
            gapsOf[token].push(
                GapRecord({
                    closePrintAt: closeAt,
                    closePrice: closeP,
                    reopenPrintAt: uint64(updatedAt),
                    reopenPrice: m.price,
                    observedAtMs: m.timestampMs,
                    gapBps: gap,
                    closureSecs: secs,
                    observedBlock: uint64(block.number)
                })
            );
            inClosure[token] = false;
            emit GapRecorded(token, closeP, m.price, gap, secs, m.timestampMs);
        }
    }

    function snapshotAll() external {
        uint256 n = tokens.length;
        for (uint256 i; i < n; ++i) {
            snapshot(tokens[i]);
        }
    }

    function gapCount(address token) external view returns (uint256) {
        return gapsOf[token].length;
    }

    function gapsPage(address token, uint256 offset, uint256 limit) external view returns (GapRecord[] memory page) {
        GapRecord[] storage g = gapsOf[token];
        uint256 n = g.length;
        if (offset >= n) return page;
        uint256 end = offset + limit > n ? n : offset + limit;
        page = new GapRecord[](end - offset);
        for (uint256 i = offset; i < end; ++i) {
            page[i - offset] = g[i];
        }
    }

    function gapStats(address token)
        external
        view
        returns (uint256 meanAbsGapBps, uint256 maxAbsGapBps, uint256 meanClosureSecs, uint256 count)
    {
        GapRecord[] storage g = gapsOf[token];
        count = g.length;
        if (count == 0) return (0, 0, 0, 0);
        uint256 sumAbs;
        uint256 sumSecs;
        for (uint256 i; i < count; ++i) {
            int256 v = g[i].gapBps;
            uint256 a = v < 0 ? uint256(-v) : uint256(v);
            sumAbs += a;
            if (a > maxAbsGapBps) maxAbsGapBps = a;
            sumSecs += g[i].closureSecs;
        }
        meanAbsGapBps = sumAbs / count;
        meanClosureSecs = sumSecs / count;
    }

    // ================================================================ configuration (RECORDER)
    /// @dev Requires an existing contract for `token` and a feed with 8 decimals, so a feed with no token
    /// cannot be registered.
    function configureToken(address token, address feed, address secondaryFeed, uint32 thresholdSecs)
        external
        onlyRecorder
    {
        if (token.code.length == 0 || feed.code.length == 0 || thresholdSecs == 0) revert BadParams();
        if (!_has8Decimals(feed)) revert BadParams();
        TokenConfig storage c = configOf[token];
        bool isNew = !c.active;
        if (isNew) tokens.push(token);
        bool secondaryChanged = isNew || c.secondaryFeed != secondaryFeed;
        if (isNew || c.feed != feed) c.registeredAt = uint64(block.timestamp);
        c.feed = feed;
        c.active = true;
        c.inSessionThresholdSecs = thresholdSecs;
        if (secondaryFeed != address(0)) {
            if (secondaryFeed.code.length == 0 || !_has8Decimals(secondaryFeed)) revert BadParams();
            if (secondaryChanged) c.secondaryRegisteredAt = uint64(block.timestamp);
        } else {
            c.secondaryRegisteredAt = 0;
        }
        c.secondaryFeed = secondaryFeed;
        emit TokenConfigured(token, feed, secondaryFeed, thresholdSecs);
    }

    function setWindow(uint32 openOffset_, uint32 closeOffset_) external onlyRecorder {
        _setWindow(openOffset_, closeOffset_);
    }

    /// @notice Declare a closure inside the weekly window. Closures must be appended in order and not overlap.
    function addClosure(uint64 start, uint64 end, ClosureKind kind) external onlyRecorder {
        if (start >= end) revert BadParams();
        uint256 n = _closures.length;
        if (n >= MAX_CLOSURES) revert TooManyClosures();
        if (n != 0 && start < _closures[n - 1].end) revert ClosureOrder();
        _closures.push(Closure(start, end, kind));
        emit ClosureAdded(start, end, kind);
    }

    /// @notice States that every closure up to `until` has been loaded. Can only move forward, at most one year ahead.
    function confirmCalendarUntil(uint64 until) external onlyRecorder {
        if (until <= confirmedUntil || until > block.timestamp + 365 days) revert BadParams();
        confirmedUntil = until;
        emit CalendarConfirmed(until);
    }

    function setRegistry(address registry_) external onlyRecorder {
        registry = registry_;
    }

    function setHeartbeat(uint32 secs, uint32 marginSecs) external onlyRecorder {
        if (secs == 0 || secs > 7 days || marginSecs > 1 days) revert BadParams();
        heartbeatSecs = secs;
        heartbeatMarginSecs = marginSecs;
    }

    function setComparisonWindow(uint32 secs) external onlyRecorder {
        if (secs == 0 || secs > 1 days) revert BadParams();
        comparisonWindowSecs = secs;
    }

    // ================================================================ internals: classification
    struct Feed {
        bool ok;
        int256 price;
        uint256 updatedAt;
    }

    function _read(address token) internal view returns (Mark memory m, uint256 updatedAt) {
        TokenConfig memory c = configOf[token];
        m.timestampMs = uint64(BaseTimeLib.timestampMs());
        if (!c.active) {
            m.session = Session.UNKNOWN;
            m.cause = Cause.NOT_CONFIGURED;
            return (m, 0);
        }

        Feed memory p = _feed(c.feed);
        updatedAt = p.updatedAt;
        if (p.ok) {
            m.price = p.price;
            m.stalenessSecs = p.updatedAt >= block.timestamp ? 0 : _sat32(block.timestamp - p.updatedAt);
        }
        m.confidenceBps = _confidence(m.stalenessSecs, p.ok);

        if (_paused(token)) {
            m.session = Session.PAUSED;
            m.cause = Cause.REGISTRY_PAUSED;
            m.confidenceBps = 0;
            return (m, updatedAt);
        }
        if (!p.ok) {
            m.session = Session.UNKNOWN;
            m.cause = Cause.FEED_INVALID;
            m.confidenceBps = 0;
            return (m, updatedAt);
        }
        if (block.timestamp > confirmedUntil) {
            m.session = Session.UNKNOWN;
            m.cause = Cause.CALENDAR_NOT_LOADED;
            m.confidenceBps = 0;
            return (m, updatedAt);
        }

        (bool open, Cause closedCause) = _openAt(block.timestamp);
        if (!open) {
            m.session = Session.CLOSED;
            m.cause = closedCause;
        } else {
            (m.session, m.cause) = _classifyOpen(p.updatedAt, c.inSessionThresholdSecs);
        }
        if (m.session != Session.FRESH) {
            m.confidenceBps = _confidence(m.stalenessSecs, true);
        }

        _divergence(m, c, p, open);
    }

    /// @dev Verdict for a print while the window is open now.
    function _classifyOpen(uint256 updatedAt, uint32 thresholdSecs) internal view returns (Session, Cause) {
        uint256 openAge = _openSeconds(updatedAt, block.timestamp);
        // Hard signal first: silent longer than the guaranteed heartbeat plus margin, counted in open time.
        if (openAge > uint256(heartbeatSecs) + heartbeatMarginSecs) {
            return (Session.STALE_IN_SESSION, Cause.HEARTBEAT_EXCEEDED);
        }
        if (openAge > thresholdSecs) return (Session.STALE_IN_SESSION, Cause.FEED_NOT_UPDATING);
        if (updatedAt < _stretchStart(block.timestamp)) {
            return (Session.STALE_IN_SESSION, Cause.AWAITING_FIRST_PRINT);
        }
        return (Session.FRESH, Cause.NONE);
    }

    function _divergence(Mark memory m, TokenConfig memory c, Feed memory p, bool open) internal view {
        if (c.secondaryFeed == address(0)) {
            m.divergenceStatus = DivergenceStatus.NO_SECONDARY;
            return;
        }
        Feed memory s = _feed(c.secondaryFeed);
        if (s.ok) {
            m.secondaryPrice = s.price;
            m.printLagSecs = _sat32(p.updatedAt > s.updatedAt ? p.updatedAt - s.updatedAt : s.updatedAt - p.updatedAt);
        }
        if (!open) {
            m.divergenceStatus = DivergenceStatus.NOT_COMPARABLE_CLOSED;
            return;
        }
        // A print outside the current open stretch cannot be FRESH, so a post-close print never reaches the
        // lag comparison: the comparison window closes with the session.
        Session ss = Session.UNKNOWN;
        if (s.ok) (ss,) = _classifyOpen(s.updatedAt, c.inSessionThresholdSecs);
        if (m.session != Session.FRESH || ss != Session.FRESH) {
            m.divergenceStatus = DivergenceStatus.NOT_COMPARABLE_FAULT;
            return;
        }
        uint256 w = comparisonWindowSecs;
        if (block.timestamp < uint256(c.registeredAt) + w || block.timestamp < uint256(c.secondaryRegisteredAt) + w) {
            m.divergenceStatus = DivergenceStatus.NOT_COMPARABLE_NEW;
            return;
        }
        if (m.printLagSecs > w) {
            m.divergenceStatus = DivergenceStatus.PRINTS_TOO_FAR_APART;
            return;
        }
        m.divergenceStatus = DivergenceStatus.COMPARED;
        m.divergenceBps = ((s.price - p.price) * 10_000) / p.price;
    }

    function _confidence(uint32 stalenessSecs, bool ok) internal pure returns (uint16) {
        if (!ok) return 0;
        if (stalenessSecs >= CONFIDENCE_HORIZON) return 0;
        return uint16(10_000 - (uint256(stalenessSecs) * 10_000) / CONFIDENCE_HORIZON);
    }

    // ================================================================ internals: calendar
    function _setWindow(uint32 o, uint32 c) internal {
        if (o >= c || c > WEEK) revert BadParams();
        weekOpenOffset = o;
        weekCloseOffset = c;
        emit WindowSet(o, c);
    }

    function _openAt(uint256 t) internal view returns (bool, Cause) {
        if (t < WEEK_ORIGIN) return (false, Cause.WEEKEND);
        uint256 w = (t - WEEK_ORIGIN) % WEEK;
        if (w < weekOpenOffset || w >= weekCloseOffset) return (false, Cause.WEEKEND);
        uint256 n = _closures.length;
        for (uint256 i; i < n; ++i) {
            Closure storage cl = _closures[i];
            if (t >= cl.start && t < cl.end) {
                return (false, cl.kind == ClosureKind.HOLIDAY ? Cause.HOLIDAY : Cause.EARLY_CLOSE);
            }
        }
        return (true, Cause.NONE);
    }

    /// @dev Open seconds in [a, b]: weekly window overlap minus closure overlap with the window.
    function _openSeconds(uint256 a, uint256 b) internal view returns (uint256) {
        if (b <= a) return 0;
        if (b - a > MAX_LOOKBACK) a = b - MAX_LOOKBACK;
        uint256 total = _weeklyOpen(a, b);
        uint256 n = _closures.length;
        for (uint256 i; i < n; ++i) {
            Closure storage cl = _closures[i];
            if (cl.end <= a) continue;
            if (cl.start >= b) break;
            uint256 s = cl.start > a ? cl.start : a;
            uint256 e = cl.end < b ? cl.end : b;
            total -= _weeklyOpen(s, e);
        }
        return total;
    }

    function _weeklyOpen(uint256 a, uint256 b) internal view returns (uint256 total) {
        if (b <= a || b <= WEEK_ORIGIN) return 0;
        if (a < WEEK_ORIGIN) a = WEEK_ORIGIN;
        uint256 w0 = (a - WEEK_ORIGIN) / WEEK;
        uint256 w1 = (b - WEEK_ORIGIN) / WEEK;
        for (uint256 w = w0; w <= w1; ++w) {
            uint256 base = WEEK_ORIGIN + w * WEEK;
            uint256 s = base + weekOpenOffset;
            uint256 e = base + weekCloseOffset;
            if (s < a) s = a;
            if (e > b) e = b;
            if (e > s) total += e - s;
        }
    }

    /// @dev Start of the continuous open stretch containing `t` (t must be open).
    function _stretchStart(uint256 t) internal view returns (uint256 start) {
        uint256 w = (t - WEEK_ORIGIN) % WEEK;
        start = t - w + weekOpenOffset;
        uint256 n = _closures.length;
        for (uint256 i; i < n; ++i) {
            Closure storage cl = _closures[i];
            if (cl.end <= t && cl.end > start) start = cl.end;
        }
    }

    // ================================================================ internals: feeds
    function _feed(address feed) internal view returns (Feed memory f) {
        (bool ok, bytes memory ret) = feed.staticcall(abi.encodeWithSignature("latestRoundData()"));
        if (!ok || ret.length < 160) return f;
        (, int256 answer,, uint256 updatedAt,) = abi.decode(ret, (uint80, int256, uint256, uint256, uint80));
        if (answer <= 0 || answer > MAX_PRICE || updatedAt == 0 || updatedAt > block.timestamp) return f;
        f.ok = true;
        f.price = answer;
        f.updatedAt = updatedAt;
    }

    function _has8Decimals(address feed) internal view returns (bool) {
        (bool ok, bytes memory ret) = feed.staticcall(abi.encodeWithSignature("decimals()"));
        return ok && ret.length >= 32 && abi.decode(ret, (uint256)) == FEED_DECIMALS;
    }

    function _paused(address token) internal view returns (bool) {
        address r = registry;
        if (r == address(0)) return false;
        (bool ok, bytes memory ret) = r.staticcall(abi.encodeWithSignature("getOracleParams(address)", token));
        if (!ok || ret.length < 64) return false;
        (, bool paused) = abi.decode(ret, (uint256, bool));
        return paused;
    }

    function _sat32(uint256 v) internal pure returns (uint32) {
        return v > type(uint32).max ? type(uint32).max : uint32(v);
    }
}
