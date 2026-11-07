// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {MockFeed, MockRegistry, MockStock} from "../src/testing/MockFeed.sol";

/// @notice SEPOLIA REHEARSAL ONLY. Run with `--account speedrun`; the keystore password is typed at runtime.
///
/// WHAT THIS VALIDATES: the deployment flow. Deployer, `--account`, the order of configuration,
/// `confirmCalendarUntil`, loading closures, and that a configured token produces each expected
/// verdict from a mock that can be put in every state.
/// WHAT IT DOES NOT VALIDATE: real feed behaviour, real window offsets, real thresholds.
///
/// EVERY NUMBER BELOW MARKED DISPOSABLE IS DELIBERATE GARBAGE. None of the window, threshold or closure
/// values here may be copied to mainnet. The script refuses to run on chain 8453.
contract RehearseSepolia is Script {
    address constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;

    // DISPOSABLE: the window is the whole week so the rehearsal works at any time it is run.
    uint32 constant DISPOSABLE_OPEN = 0;
    uint32 constant DISPOSABLE_CLOSE = 7 days;
    // DISPOSABLE: threshold used for every rehearsal token.
    uint32 constant DISPOSABLE_THRESHOLD = 2 hours;

    SessionOracle openOracle;
    SessionOracle closedOracle;

    function run() external {
        require(block.chainid != 8453, "REHEARSAL: never on mainnet");
        uint256 t = block.timestamp;

        vm.startBroadcast(DEPLOYER);

        // --- oracle A: always open, with one recent closure so a stretch start exists
        openOracle = new SessionOracle(DEPLOYER, DISPOSABLE_OPEN, DISPOSABLE_CLOSE, 24 hours, 1 hours, 10 minutes);
        openOracle.confirmCalendarUntil(uint64(t + 30 days));
        openOracle.addClosure(uint64(t - 2 hours), uint64(t - 1 hours), SessionOracle.ClosureKind.HOLIDAY); // DISPOSABLE
        // DISPOSABLE stand-in for the Thanksgiving closure; the real intervals are loaded on mainnet only.
        openOracle.addClosure(uint64(t + 5 days), uint64(t + 6 days), SessionOracle.ClosureKind.HOLIDAY);

        MockRegistry reg = new MockRegistry();
        openOracle.setRegistry(address(reg));

        MockFeed[8] memory f;
        MockStock[8] memory s;
        for (uint256 i; i < 8; ++i) {
            f[i] = new MockFeed();
            s[i] = new MockStock("MOCK");
            openOracle.configureToken(address(s[i]), address(f[i]), address(0), DISPOSABLE_THRESHOLD);
        }
        f[0].set(100e8, t - 60); // FRESH
        f[1].set(100e8, t - 70 minutes); // AWAITING_FIRST_PRINT (print predates the stretch start, inside threshold)
        f[2].set(100e8, t - 5 hours); // FEED_NOT_UPDATING
        f[3].set(100e8, t - 30 hours); // HEARTBEAT_EXCEEDED
        f[4].set(100e8, t + 1 days); // future-dated -> FEED_INVALID
        f[5].set(2e20, t - 60); // absurd price -> FEED_INVALID
        f[6].set(100e8, t - 60); // PAUSED by the registry
        reg.setPaused(address(s[6]), true);
        f[7].set(100e8, t - 60);
        f[7].setReverts(true); // FEED_INVALID

        // --- oracle B: the window is placed so that "now" is outside it
        uint256 w = (t - 4 days) % 7 days;
        uint32 o = w < 7 days - 3 hours ? uint32(w + 1 hours) : 0;
        uint32 c = w < 7 days - 3 hours ? uint32(w + 2 hours) : 1 hours;
        closedOracle = new SessionOracle(DEPLOYER, o, c, 24 hours, 1 hours, 10 minutes);
        closedOracle.confirmCalendarUntil(uint64(t + 30 days));
        MockFeed fc = new MockFeed();
        MockStock sc = new MockStock("MOCKCLOSED");
        closedOracle.configureToken(address(sc), address(fc), address(0), DISPOSABLE_THRESHOLD);
        fc.set(100e8, t - 3 hours);

        vm.stopBroadcast();

        _expect(openOracle, address(s[0]), ISessionOracle.Session.FRESH, ISessionOracle.Cause.NONE);
        _expect(openOracle, address(s[1]), ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.AWAITING_FIRST_PRINT);
        _expect(openOracle, address(s[2]), ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.FEED_NOT_UPDATING);
        _expect(openOracle, address(s[3]), ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.HEARTBEAT_EXCEEDED);
        _expect(openOracle, address(s[4]), ISessionOracle.Session.UNKNOWN, ISessionOracle.Cause.FEED_INVALID);
        _expect(openOracle, address(s[5]), ISessionOracle.Session.UNKNOWN, ISessionOracle.Cause.FEED_INVALID);
        _expect(openOracle, address(s[6]), ISessionOracle.Session.PAUSED, ISessionOracle.Cause.REGISTRY_PAUSED);
        _expect(openOracle, address(s[7]), ISessionOracle.Session.UNKNOWN, ISessionOracle.Cause.FEED_INVALID);
        _expect(closedOracle, address(sc), ISessionOracle.Session.CLOSED, ISessionOracle.Cause.WEEKEND);

        console.log("openOracle  ", address(openOracle));
        console.log("closedOracle", address(closedOracle));
        console.log("All expected verdicts matched. Parameters were disposable; do not reuse them.");
    }

    function _expect(SessionOracle o, address token, ISessionOracle.Session sess, ISessionOracle.Cause cause)
        internal
        view
    {
        ISessionOracle.Mark memory m = o.markOf(token);
        require(m.session == sess && m.cause == cause, "REHEARSAL: unexpected verdict");
    }
}
