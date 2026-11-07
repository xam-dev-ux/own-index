// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";

interface IFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/// @dev Mainnet fork pinned to a Saturday (2026-11-07). Run with --fork-url and --fork-block-number 54457318.
contract SessionOracleForkTest is Test {
    address constant AAPLC = 0xb200000000000000000000C2e324d24d7eEcd1fb;
    address constant AAPL_FEED = 0x787f13dEa48Db0897CbCDD985de77809D837F988;
    address constant NVDAC = 0xb20000000000000000000078ee7ce2fE4908108C;
    address constant NVDA_FEED = 0x04689a41629776563E6822F76f2e57D148d28513;
    address constant NVDA_247 = 0x48D9731AF6cc55b879FE76a4Bd1A6c2C0bDaf944;
    address constant RECORDER = address(0xBEEF);
    SessionOracle o;

    function setUp() public {
        if (block.chainid != 8453) vm.skip(true);
        o = new SessionOracle(RECORDER, 1 hours, 5 days + 1 hours, 24 hours, 1 hours, 10 minutes);
        vm.startPrank(RECORDER);
        o.confirmCalendarUntil(uint64(block.timestamp + 30 days));
        o.configureToken(AAPLC, AAPL_FEED, address(0), 4 hours);
        o.configureToken(NVDAC, NVDA_FEED, NVDA_247, 4 hours);
        vm.stopPrank();
    }

    function test_staleness_matches_hand_computation_and_weekend_is_closed() public view {
        (, int256 ans,, uint256 upd,) = IFeed(AAPL_FEED).latestRoundData();
        ISessionOracle.Mark memory m = o.markOf(AAPLC);
        assertEq(m.price, ans);
        assertEq(uint256(m.stalenessSecs), block.timestamp - upd);
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.CLOSED));
        assertEq(uint8(m.cause), uint8(ISessionOracle.Cause.WEEKEND));
        assertFalse(o.isFresh(AAPLC));
        // The flat 26h rule would have called this fresh; here the print is under 26h old and CLOSED anyway.
        assertLt(uint256(m.stalenessSecs), 26 hours);
    }

    function test_secondary_feed_reported_but_not_compared_while_closed() public view {
        ISessionOracle.Mark memory m = o.markOf(NVDAC);
        assertGt(m.secondaryPrice, 0);
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.NOT_COMPARABLE_CLOSED));
    }
}
