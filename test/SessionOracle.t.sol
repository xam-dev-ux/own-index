// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {MockAggregator, MockRegistry, MockToken} from "./mocks/MockAggregator.sol";
import {MockBaseTime} from "./mocks/MockBaseTime.sol";

/// @dev Thresholds here are injected test values. They are NOT the production defaults, which are pending
/// the measured inter-print distributions.
contract SessionOracleTest is Test {
    uint256 constant MON = 1794182400;          // Monday 2026-11-09 00:00 UTC
    uint32 constant OPEN_OFF = 1 hours;         // Monday 01:00 UTC
    uint32 constant CLOSE_OFF = 5 days + 1 hours; // Saturday 01:00 UTC
    uint32 constant THRESH = 4 hours;           // injected
    address constant RECORDER = address(0xBEEF);
    address constant BASE_TIME = 0x4200000000000000000000000000000000000030;

    SessionOracle o;
    MockAggregator feed;
    MockAggregator feed2;
    MockToken tok;

    function setUp() public {
        vm.warp(MON);
        o = new SessionOracle(RECORDER, OPEN_OFF, CLOSE_OFF, 24 hours, 1 hours, 10 minutes);
        feed = new MockAggregator();
        feed2 = new MockAggregator();
        tok = new MockToken();
        vm.startPrank(RECORDER);
        o.confirmCalendarUntil(uint64(MON + 60 days));
        o.configureToken(address(tok), address(feed), address(0), THRESH);
        vm.stopPrank();
    }

    function _at(uint256 offset) internal { vm.warp(MON + offset); }
    function _print(int256 px, uint256 offset) internal { feed.set(px, MON + offset); }
    function _m() internal view returns (ISessionOracle.Mark memory) { return o.markOf(address(tok)); }

    // ------------------------------------------------------------ verdicts
    function test_fresh_inside_threshold() public {
        _at(1 days + 12 hours);
        _print(100e8, 1 days + 11 hours + 30 minutes);
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.FRESH));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.NONE));
        assertEq(uint256(m.confidenceBps), uint256(10_000) - (uint256(1800) * 10_000) / uint256(7 days));
        assertTrue(o.isFresh(address(tok)));
    }

    function test_stale_beyond_threshold_is_FEED_NOT_UPDATING() public {
        _at(1 days + 12 hours);
        _print(100e8, 1 days + 7 hours);
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.STALE_IN_SESSION));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.FEED_NOT_UPDATING));
    }

    function test_heartbeat_is_a_separate_cause_from_threshold() public {
        vm.prank(RECORDER);
        o.configureToken(address(tok), address(feed), address(0), 30 days); // threshold cannot fire
        _at(3 days + 12 hours);
        _print(100e8, 1 days + 2 hours); // 58h open silence
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.HEARTBEAT_EXCEEDED));
        // 24h silence exactly + margin is not yet exceeded
        _print(100e8, 3 days + 12 hours - 25 hours);
        assertTrue(_m().cause != ISessionOracle.Cause.HEARTBEAT_EXCEEDED);
    }

    function test_weekend_silence_is_CLOSED_not_heartbeat() public {
        _print(100e8, 4 days + 10 hours); // Friday print, 29h before Saturday 15:00
        _at(5 days + 15 hours);           // Saturday 15:00
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.CLOSED));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.WEEKEND));
        assertGt(uint256(m.stalenessSecs), 24 hours);
    }

    function test_reopen_held_print_is_AWAITING_not_fresh_not_heartbeat() public {
        _print(100e8, 4 days + 22 hours);
        _at(7 days + 1 hours + 30 minutes); // next Monday 01:30
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.STALE_IN_SESSION));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.AWAITING_FIRST_PRINT));
        // a print inside the new stretch makes it fresh
        _print(101e8, 7 days + 1 hours + 10 minutes);
        assertEq(uint8(_m().session), uint8(ISessionOracle.Session.FRESH));
    }

    function test_holiday_and_early_close_use_the_declared_day() public {
        // Full holiday Wed 00:00 to Thu 00:00, early close Fri 18:00 to Sat 01:00
        vm.startPrank(RECORDER);
        o.addClosure(uint64(MON + 2 days), uint64(MON + 3 days), SessionOracle.ClosureKind.HOLIDAY);
        o.addClosure(uint64(MON + 4 days + 18 hours), uint64(MON + 5 days + 1 hours), SessionOracle.ClosureKind.EARLY_CLOSE);
        vm.stopPrank();
        _print(100e8, 1 days + 22 hours);
        _at(2 days + 12 hours);
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.HOLIDAY));
        _print(100e8, 4 days + 17 hours);
        _at(4 days + 19 hours);
        assertEq(uint8(_m().session), uint8(ISessionOracle.Session.CLOSED));
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.EARLY_CLOSE));
        // 17:30 the same day is still open
        _at(4 days + 17 hours + 30 minutes);
        assertEq(uint8(_m().session), uint8(ISessionOracle.Session.FRESH));
    }

    function test_holiday_time_is_not_counted_toward_staleness() public {
        vm.prank(RECORDER);
        o.addClosure(uint64(MON + 2 days), uint64(MON + 3 days), SessionOracle.ClosureKind.HOLIDAY);
        _print(100e8, 1 days + 22 hours);
        _at(3 days + 1 hours); // Thursday 01:00: 3h of open time since the print, 27h wall clock
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.AWAITING_FIRST_PRINT));
    }

    function test_calendar_beyond_horizon_is_UNKNOWN() public {
        _print(100e8, 1 days);
        vm.warp(MON + 61 days);
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.UNKNOWN));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.CALENDAR_NOT_LOADED));
    }

    function test_paused_and_invalid_and_unconfigured() public {
        _at(1 days);
        _print(100e8, 1 days - 1 minutes);
        MockRegistry reg = new MockRegistry();
        vm.prank(RECORDER);
        o.setRegistry(address(reg));
        reg.setPaused(true);
        assertEq(uint8(_m().session), uint8(ISessionOracle.Session.PAUSED));
        reg.setPaused(false);
        feed.setReverts(true);
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.FEED_INVALID));
        feed.setReverts(false);
        feed.setShort(true);
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.FEED_INVALID));
        feed.setShort(false);
        feed.set(-5, MON);
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.FEED_INVALID));
        feed.set(100e8, 0);
        assertEq(uint8(_m().cause), uint8(ISessionOracle.Cause.FEED_INVALID));
        assertEq(uint8(o.markOf(address(0x1234)).cause), uint8(ISessionOracle.Cause.NOT_CONFIGURED));
    }

    // ------------------------------------------------------------ never reverts, confidence
    function testFuzz_markOf_never_reverts(uint32 staleness, uint256 updatedAt, int256 answer, uint32 nowOff) public {
        vm.warp(MON + (uint256(nowOff) % 50 days));
        feed.set(answer, updatedAt);
        o.markOf(address(tok));
        feed.set(100e8, block.timestamp > staleness ? block.timestamp - staleness : 0);
        o.markOf(address(tok));
    }

    function testFuzz_confidence_monotonic(uint32 a, uint32 b) public {
        (a, b) = a <= b ? (a, b) : (b, a);
        a = uint32(bound(a, 0, MON));
        b = uint32(bound(b, a, MON));
        vm.warp(MON + 1 days);
        feed.set(100e8, block.timestamp - a);
        uint16 ca = _m().confidenceBps;
        feed.set(100e8, block.timestamp - b);
        // staleness larger => confidence not larger, regardless of verdict
        assertLe(uint256(_m().confidenceBps), uint256(ca));
    }

    function test_staleness_saturates_at_uint32() public {
        vm.warp(10_000_000_000);
        feed.set(100e8, 1);
        assertEq(uint256(_m().stalenessSecs), uint256(type(uint32).max));
        assertEq(uint256(_m().confidenceBps), 0);
    }

    function test_never_reverts_with_zero_updatedAt() public {
        _at(1 days);
        feed.set(100e8, 0);
        _m();
    }

    // ------------------------------------------------------------ gap ledger
    function _closeThenReopen(int256 closePx, int256 openPx) internal {
        _print(closePx, 4 days + 22 hours);
        _at(5 days + 12 hours);
        o.snapshot(address(tok));
        _at(7 days + 1 hours + 5 minutes);
        _print(openPx, 7 days + 1 hours + 2 minutes);
        o.snapshot(address(tok));
    }

    function test_closure_detected_once() public {
        _print(100e8, 4 days + 22 hours);
        _at(5 days + 12 hours);
        vm.recordLogs();
        o.snapshot(address(tok));
        o.snapshot(address(tok));
        o.snapshotAll();
        assertEq(vm.getRecordedLogs().length, 1);
        assertTrue(o.inClosure(address(tok)));
    }

    function test_gap_recorded_with_sign_and_magnitude() public {
        _closeThenReopen(100e8, 98e8);
        assertEq(o.gapCount(address(tok)), 1);
        SessionOracle.GapRecord[] memory g = o.gapsPage(address(tok), 0, 10);
        assertEq(g[0].gapBps, -200);
        assertEq(g[0].closePrice, 100e8);
        assertEq(g[0].reopenPrice, 98e8);
        assertFalse(o.inClosure(address(tok)));
    }

    function test_gap_closureSecs_exact() public {
        _closeThenReopen(100e8, 103e8);
        SessionOracle.GapRecord[] memory g = o.gapsPage(address(tok), 0, 1);
        assertEq(g[0].gapBps, 300);
        assertEq(uint256(g[0].closureSecs), (7 days + 1 hours + 2 minutes) - (4 days + 22 hours));
    }

    function test_no_gap_without_closure() public {
        _at(1 days);
        _print(100e8, 1 days - 1 minutes);
        o.snapshot(address(tok));
        _print(120e8, 1 days - 30);
        o.snapshot(address(tok));
        assertEq(o.gapCount(address(tok)), 0);
    }

    function test_snapshot_unknown_token_reverts() public {
        vm.expectRevert(abi.encodeWithSelector(SessionOracle.UnknownToken.selector, address(0xdead)));
        o.snapshot(address(0xdead));
    }

    function test_gapStats() public {
        (uint256 a, uint256 mx, uint256 c, uint256 n) = o.gapStats(address(tok));
        assertEq(n, 0); assertEq(a + mx + c, 0);
        _closeThenReopen(100e8, 98e8); // -200
        (a, mx, c, n) = o.gapStats(address(tok));
        assertEq(n, 1); assertEq(a, 200); assertEq(mx, 200);
        // second week: +400
        uint256 w = 7 days;
        feed.set(98e8, MON + w + 4 days + 22 hours);
        vm.warp(MON + w + 5 days + 12 hours);
        o.snapshot(address(tok));
        vm.warp(MON + 2 * w + 1 hours + 5 minutes);
        feed.set(10_192_000_000, MON + 2 * w + 1 hours + 2 minutes); // 98 * 1.04
        o.snapshot(address(tok));
        (a, mx, c, n) = o.gapStats(address(tok));
        assertEq(n, 2); assertEq(a, 300); assertEq(mx, 400);
    }

    // ------------------------------------------------------------ permissions
    function testFuzz_snapshot_is_permissionless(address caller) public {
        vm.assume(caller != address(0));
        _print(100e8, 4 days + 22 hours);
        _at(5 days + 12 hours);
        vm.prank(caller);
        o.snapshot(address(tok));
        assertTrue(o.inClosure(address(tok)));
    }

    function testFuzz_recorder_only(address caller) public {
        vm.assume(caller != RECORDER);
        vm.startPrank(caller);
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.configureToken(address(tok), address(feed), address(0), 1);
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.setWindow(1, 2);
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.addClosure(1, 2, SessionOracle.ClosureKind.HOLIDAY);
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.confirmCalendarUntil(uint64(block.timestamp + 1));
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.setRegistry(address(1));
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.setHeartbeat(1, 1);
        vm.expectRevert(SessionOracle.NotRecorder.selector);
        o.setComparisonWindow(1);
        vm.stopPrank();
    }

    function test_orphan_feed_cannot_be_registered() public {
        vm.startPrank(RECORDER);
        vm.expectRevert(SessionOracle.BadParams.selector);
        o.configureToken(address(0x9999), address(feed), address(0), THRESH); // no token contract
        feed.setDecimals(18);
        vm.expectRevert(SessionOracle.BadParams.selector);
        o.configureToken(address(tok), address(feed), address(0), THRESH);
        vm.stopPrank();
    }

    function test_closures_must_be_ordered_and_bounded() public {
        vm.startPrank(RECORDER);
        o.addClosure(100, 200, SessionOracle.ClosureKind.HOLIDAY);
        vm.expectRevert(SessionOracle.ClosureOrder.selector);
        o.addClosure(150, 300, SessionOracle.ClosureKind.HOLIDAY);
        vm.stopPrank();
    }

    // ------------------------------------------------------------ divergence
    function _second() internal {
        vm.prank(RECORDER);
        o.configureToken(address(tok), address(feed), address(feed2), THRESH);
        vm.warp(block.timestamp + 1 hours); // outlive the comparison window
    }

    function test_divergence_compared_new_and_lag() public {
        _at(1 days);
        vm.prank(RECORDER);
        o.configureToken(address(tok), address(feed), address(feed2), THRESH);
        _print(100e8, 1 days - 5 minutes);
        feed2.set(99e8, MON + 1 days - 5 minutes);
        assertEq(uint8(_m().divergenceStatus), uint8(ISessionOracle.DivergenceStatus.NOT_COMPARABLE_NEW));
        _at(1 days + 1 hours);
        _print(100e8, 1 days + 1 hours - 5 minutes);
        feed2.set(99e8, MON + 1 days + 1 hours - 5 minutes);
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.COMPARED));
        assertEq(m.divergenceBps, -100);
        assertEq(m.secondaryPrice, 99e8);
        // primary price is never replaced
        assertEq(m.price, 100e8);
        // prints 47 minutes apart: lag, not disagreement
        feed2.set(99e8, MON + 1 days + 1 hours - 52 minutes);
        m = _m();
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.PRINTS_TOO_FAR_APART));
        assertEq(uint256(m.printLagSecs), 47 minutes);
        assertEq(m.divergenceBps, 0);
    }

    function test_divergence_closed_market_is_not_an_anomaly() public {
        _second();
        _at(5 days + 12 hours);
        feed.set(100e8, MON + 4 days + 22 hours);
        feed2.set(99e8, MON + 4 days + 23 hours + 39 minutes); // post-close print on the other feed
        ISessionOracle.Mark memory m = _m();
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.CLOSED));
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.NOT_COMPARABLE_CLOSED));
    }

    function test_divergence_old_session_print_never_compared_after_reopen() public {
        _at(1 days);
        _second();
        _at(7 days + 1 hours + 30 minutes);   // fresh session; secondary still on last week's print
        feed.set(100e8, MON + 7 days + 1 hours + 20 minutes);
        feed2.set(99e8, MON + 4 days + 23 hours);
        assertEq(uint8(_m().divergenceStatus), uint8(ISessionOracle.DivergenceStatus.NOT_COMPARABLE_FAULT));
    }

    function test_no_secondary() public {
        assertEq(uint8(_m().divergenceStatus), uint8(ISessionOracle.DivergenceStatus.NO_SECONDARY));
    }

    // ------------------------------------------------------------ BaseTime
    function test_timestampMs_fallback_without_basetime() public {
        _at(1 days);
        assertEq(_m().timestampMs, (MON + 1 days) * 1000);
    }

    function test_timestampMs_uses_basetime_when_active() public {
        MockBaseTime bt = new MockBaseTime();
        vm.etch(BASE_TIME, address(bt).code);
        MockBaseTime(BASE_TIME).setMillisPart(400);
        _at(1 days);
        assertEq(_m().timestampMs, (MON + 1 days) * 1000 + 400);
    }

    // ------------------------------------------------------------ calendar maths
    function testFuzz_openSeconds_bounded(uint32 a, uint32 b) public view {
        uint256 x = MON + uint256(a) % 40 days;
        uint256 y = MON + uint256(b) % 40 days;
        if (y < x) (x, y) = (y, x);
        uint256 s = o.openSecondsBetween(x, y);
        assertLe(s, y - x);
    }

    function test_openSeconds_exact_week() public view {
        assertEq(o.openSecondsBetween(MON, MON + 7 days), uint256(CLOSE_OFF - OPEN_OFF));
    }

    /// @dev The verdict the vault consumes depends only on live feed state, never on the ledger or on
    /// whether anyone called snapshot().
    function test_markOf_independent_of_ledger_state() public {
        _print(100e8, 4 days + 22 hours);
        _at(5 days + 12 hours);
        ISessionOracle.Mark memory before_ = _m();
        o.snapshot(address(tok));
        assertEq(abi.encode(before_), abi.encode(_m()));
        _at(7 days + 1 hours + 30 minutes);
        _print(90e8, 7 days + 1 hours + 10 minutes);
        ISessionOracle.Mark memory unrecorded = _m();
        o.snapshot(address(tok));
        assertEq(abi.encode(unrecorded), abi.encode(_m()));
    }
}
