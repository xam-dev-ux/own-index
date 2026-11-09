// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";

/// @notice The two comparison states that had only been exercised with mocks, run against the REAL oracle and the REAL
/// Chainlink Coinbase feeds at four historical blocks of Monday 2026-11-09, chosen from data/feed_samples_247.csv.
///
/// Each case forks the chain at a block where the 24/5 feed and its 24/7 sibling hold the prints listed below, deploys
/// the oracle with the mainnet parameters (deploy/mainnet.params.env), registers the pair, and moves time forward just
/// past the comparison window so the pair is no longer "new". Only time moves: every price and print time is the chain's.
///
///   block     token  primary updatedAt  secondary updatedAt  lag     expected
///   55100225  GOOGL  (CSV)              (CSV)                410 s   COMPARED
///   55099732  TSLA   (CSV)              (CSV)                356 s   COMPARED
///   55098089  GOOGL  (CSV)              (CSV)                3942 s  PRINTS_TOO_FAR_APART (window 3600)
///   55090701  TSLA   (CSV)              (CSV)                4769 s  PRINTS_TOO_FAR_APART
contract SessionOracleRealPrintsForkTest is Test {
    address constant REGISTRY = 0x3f3E8cf41cdd3b1D118c16471aB0113DfDDd5CaD;
    address constant GOOGL = 0xb2000000000000000000002D0BA3164cc74f58B7;
    address constant GOOGL_FEED = 0x5bF49E0ffA937CE2FfF033c739aD7C634c4D34F2;
    address constant GOOGL_247 = 0xdD9b9EC942477AA672a15adF91AC5089BD86cD85;
    address constant TSLA = 0xb2000000000000000000001e800a7f5189430cD0;
    address constant TSLA_FEED = 0xFaf869185383a24F8cb00e27BdA6b63B9905DCb4;
    address constant TSLA_247 = 0xa5Ccd0315346b9A8A1D0AFEcD7Cc4e820e405e96;

    uint32 constant WINDOW = 3600; // deploy/mainnet.params.env ORACLE_COMPARISON_WINDOW

    function setUp() public {
        // These suites run on a mainnet fork (make test-fork). The cases below select their own historical blocks.
        if (block.chainid != 8453) vm.skip(true);
    }

    function _rpc() internal view returns (string memory) {
        return vm.envOr("MAINNET_RPC", string("https://mainnet.base.org"));
    }

    function _read(address feed) internal view returns (int256 answer, uint256 updatedAt) {
        (, answer, , updatedAt,) = ISessionOracleFeed(feed).latestRoundData();
    }

    /// Forks at `blockNumber`, deploys the mainnet-parameter oracle, and returns the verdict once the pair is past its
    /// registration window. Also returns the raw feed answers so the test can recompute the expected divergence itself.
    function _run(uint256 blockNumber, address token, address feed, address secondary)
        internal
        returns (ISessionOracle.Mark memory m, int256 pa, uint256 pu, int256 sa, uint256 su)
    {
        vm.createSelectFork(_rpc(), blockNumber);
        SessionOracle o = new SessionOracle(address(this), 3600, 435600, 86400, 3600, WINDOW);
        o.confirmCalendarUntil(uint64(block.timestamp + 30 days));
        o.setRegistry(REGISTRY);
        o.configureToken(token, feed, secondary, 50400);
        (pa, pu) = _read(feed);
        (sa, su) = _read(secondary);
        vm.warp(block.timestamp + WINDOW + 1);
        m = o.markOf(token);
    }

    function _bps(int256 sec, int256 pri) internal pure returns (int256) {
        return ((sec - pri) * 10_000) / pri;
    }

    function _lag(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function test_googl_prints_close_together_are_compared() public {
        (ISessionOracle.Mark memory m, int256 pa, uint256 pu, int256 sa, uint256 su) =
            _run(55100225, GOOGL, GOOGL_FEED, GOOGL_247);
        assertEq(_lag(pu, su), 410, "the chain holds the prints the CSV recorded");
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.FRESH));
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.COMPARED));
        assertEq(m.printLagSecs, 410);
        assertEq(m.divergenceBps, _bps(sa, pa));
        assertEq(m.divergenceBps, 28, "0.29% between the 24/5 and the 24/7 price, from the chain");
    }

    function test_tsla_prints_close_together_are_compared() public {
        (ISessionOracle.Mark memory m, int256 pa, uint256 pu, int256 sa, uint256 su) =
            _run(55099732, TSLA, TSLA_FEED, TSLA_247);
        assertEq(_lag(pu, su), 356);
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.FRESH));
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.COMPARED));
        assertEq(m.divergenceBps, _bps(sa, pa));
    }

    function test_googl_prints_an_hour_apart_are_lag_not_disagreement() public {
        (ISessionOracle.Mark memory m,, uint256 pu,, uint256 su) = _run(55098089, GOOGL, GOOGL_FEED, GOOGL_247);
        assertEq(_lag(pu, su), 3942);
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.FRESH), "both prints are fresh; the verdict is unaffected");
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.PRINTS_TOO_FAR_APART));
        assertEq(m.printLagSecs, 3942);
    }

    function test_tsla_prints_far_apart_are_lag_not_disagreement() public {
        (ISessionOracle.Mark memory m,, uint256 pu,, uint256 su) = _run(55090701, TSLA, TSLA_FEED, TSLA_247);
        assertEq(_lag(pu, su), 4769);
        assertEq(uint8(m.session), uint8(ISessionOracle.Session.FRESH));
        assertEq(uint8(m.divergenceStatus), uint8(ISessionOracle.DivergenceStatus.PRINTS_TOO_FAR_APART));
    }
}

interface ISessionOracleFeed {
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}
