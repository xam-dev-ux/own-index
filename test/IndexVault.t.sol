// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, Vm} from "forge-std/Test.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {MockToken, MockRouter, MockOracle} from "../src/testing/MockTrade.sol";

contract IndexVaultTest is Test {
    MockOracle oracle;
    MockRouter router;
    MockToken usdc;
    MockToken a; // $100
    MockToken b; // $50
    IndexVaultFactory factory;
    IndexVault vault;
    address user = address(0xA11CE);
    address attacker = address(0xBAD);

    uint256 constant CAP = 5_000e6;

    function setUp() public {
        vm.warp(1_800_000_000);
        oracle = new MockOracle();
        router = new MockRouter();
        usdc = new MockToken("USDC", 6);
        a = new MockToken("A", 8);
        b = new MockToken("B", 8);
        oracle.fresh(address(a), 100e8);
        oracle.fresh(address(b), 50e8);
        address[] memory toks = new address[](2);
        toks[0] = address(a);
        toks[1] = address(b);
        uint256[] memory caps = new uint256[](2);
        caps[0] = CAP;
        caps[1] = CAP;
        factory = new IndexVaultFactory(oracle, address(usdc), address(router), 1 hours, toks, caps);
        vm.prank(user);
        vault = IndexVault(factory.createVault());

        IIndexVault.Component[] memory c = new IIndexVault.Component[](2);
        c[0] = IIndexVault.Component(address(a), 5000);
        c[1] = IIndexVault.Component(address(b), 5000);
        vm.startPrank(user);
        vault.setComponents(c);
        vault.setRules(IIndexVault.Rules({driftThresholdBps: 500, minRebalanceInterval: 1 hours, maxSlippageBps: 100}));
        vm.stopPrank();

        // router inventory and user funds
        a.mint(address(router), 1e14);
        b.mint(address(router), 1e14);
        usdc.mint(address(router), 1e14);
        usdc.mint(user, 1_000_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    // ---- helpers
    function _swap(address tin, uint256 ain, address tout, uint256 aout) internal view returns (bytes memory) {
        return abi.encodeCall(MockRouter.swap, (tin, ain, tout, aout, address(vault)));
    }

    /// 1000 USDC -> 5 A ($500) + 10 B ($500). Leaves 0 USDC.
    function _fund() internal {
        bytes[] memory s = new bytes[](2);
        s[0] = _swap(address(usdc), 500e6, address(a), 5e8);
        s[1] = _swap(address(usdc), 500e6, address(b), 10e8);
        vm.prank(user);
        vault.deposit(1000e6, s);
    }

    /// Skews the vault: it holds 8 A ($800) and 4 B ($200) -> 80/20.
    function _skew() internal {
        a.mint(address(vault), 3e8);
        vm.prank(address(vault));
        b.transfer(address(router), 6e8);
    }

    function _rebalanceSwaps() internal view returns (bytes[] memory s) {
        // sell 3 A ($300) for 6 B ($300)
        s = new bytes[](1);
        s[0] = _swap(address(a), 3e8, address(b), 6e8);
    }

    // ================================================================ gating and mapping

    function test_fund_and_values() public {
        _fund();
        (uint256 v, bool fresh) = vault.totalValue();
        assertEq(v, 1000e6);
        assertTrue(fresh);
        assertEq(vault.currentWeights()[0], 5000);
    }

    function test_multiplier_is_not_applied_twice() public {
        _fund();
        a.setMultiplier(2e18); // display multiplier changes...
        (uint256 v,) = vault.totalValue();
        assertEq(v, 1000e6); // ...valuation does not
        assertEq(vault.scaledHoldings()[0], 10e8); // display only
    }

    function test_refusal_mapping_one_to_one() public {
        _fund();
        _skew();
        bytes[] memory s = _rebalanceSwaps();
        ISessionOracle.Session CL = ISessionOracle.Session.CLOSED;

        oracle.set(address(a), 100e8, CL, ISessionOracle.Cause.WEEKEND);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.MarketClosed.selector, address(a), ISessionOracle.Cause.WEEKEND));
        vault.rebalance(s);

        oracle.set(address(a), 100e8, CL, ISessionOracle.Cause.HOLIDAY);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.MarketClosed.selector, address(a), ISessionOracle.Cause.HOLIDAY));
        vault.rebalance(s);

        oracle.set(address(a), 100e8, ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.AWAITING_FIRST_PRINT);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.AwaitingFirstPrint.selector, address(a)));
        vault.rebalance(s);

        oracle.set(address(a), 100e8, ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.FEED_NOT_UPDATING);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.FeedFault.selector, address(a), ISessionOracle.Cause.FEED_NOT_UPDATING));
        vault.rebalance(s);

        oracle.set(address(a), 100e8, ISessionOracle.Session.UNKNOWN, ISessionOracle.Cause.CALENDAR_NOT_LOADED);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.FeedFault.selector, address(a), ISessionOracle.Cause.CALENDAR_NOT_LOADED));
        vault.rebalance(s);

        oracle.set(address(a), 100e8, ISessionOracle.Session.PAUSED, ISessionOracle.Cause.REGISTRY_PAUSED);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.CorporateActionPause.selector, address(a)));
        vault.rebalance(s);

        oracle.fresh(address(a), 100e8);
        a.setEffectiveAt(block.timestamp + 30 minutes);
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IIndexVault.MultiplierChangeImminent.selector, address(a), block.timestamp + 30 minutes)
        );
        vault.rebalance(s);

        a.setEffectiveAt(block.timestamp + 2 hours); // outside the window: fine
        vm.prank(user);
        vault.rebalance(s);
    }

    function test_oracle_reverting_is_a_feed_fault() public {
        _fund();
        _skew();
        oracle.setReverts(true);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.FeedFault.selector, address(a), ISessionOracle.Cause.FEED_INVALID));
        vault.rebalance(_rebalanceSwaps());
    }

    function test_no_drift_and_too_soon() public {
        _fund();
        vm.prank(user);
        vm.expectRevert(IIndexVault.NoDriftDetected.selector);
        vault.rebalance(new bytes[](0));

        _skew();
        vm.prank(user);
        vault.rebalance(_rebalanceSwaps());
        assertEq(vault.currentWeights()[0], 5000);

        _skew();
        uint64 next = vault.lastRebalanceAt() + 1 hours;
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.RebalanceTooSoon.selector, next));
        vault.rebalance(_rebalanceSwaps());
        vm.warp(next);
        vm.prank(user);
        vault.rebalance(_rebalanceSwaps());
        assertEq(vault.rebalanceCount(), 2);
    }

    // ================================================================ the two entry points cannot diverge

    /// For every verdict a component can have: rebalance reverts <=> tryRebalance returns false,
    /// and rebalanceStatus agrees with both.
    function testFuzz_entry_points_agree(uint8 sessionRaw, uint8 causeRaw, bool imminent) public {
        _fund();
        _skew();
        ISessionOracle.Session sess = ISessionOracle.Session(bound(sessionRaw, 0, 4));
        ISessionOracle.Cause cause = ISessionOracle.Cause(bound(causeRaw, 0, 10));
        oracle.set(address(b), 50e8, sess, cause);
        if (imminent) a.setEffectiveAt(block.timestamp + 10 minutes);
        bytes[] memory s = _rebalanceSwaps();

        (bool possible, IIndexVault.Refusal[] memory rs,,) = vault.rebalanceStatus();

        uint256 snap = vm.snapshotState();
        vm.prank(user);
        (bool ok,) = address(vault).call(abi.encodeCall(IIndexVault.rebalance, (s)));
        vm.revertToState(snap);
        vm.prank(user);
        bool executed = vault.tryRebalance(s);

        assertEq(ok, executed, "simulation and execution disagree");
        assertEq(possible, executed, "status disagrees");
        if (!executed) {
            assertEq(vault.refusalCount(), 1);
            assertGt(rs.length, 0);
        }
    }

    // ================================================================ recording path

    function test_tryRebalance_records_instead_of_reverting() public {
        _fund();
        _skew();
        oracle.set(address(a), 100e8, ISessionOracle.Session.CLOSED, ISessionOracle.Cause.WEEKEND);
        oracle.set(address(b), 50e8, ISessionOracle.Session.STALE_IN_SESSION, ISessionOracle.Cause.AWAITING_FIRST_PRINT);

        vm.recordLogs();
        vm.prank(user);
        bool executed = vault.tryRebalance(_rebalanceSwaps());
        assertFalse(executed);
        assertEq(vault.refusalCount(), 1);
        assertEq(vault.rebalanceCount(), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2); // one per offending component
        assertEq(logs[0].topics[0], IIndexVault.RebalanceRefused.selector);
        assertEq(uint256(logs[0].topics[1]), 1); // same refusalId for the whole call
        assertEq(uint256(logs[1].topics[1]), 1);
        // nothing moved
        assertEq(a.balanceOf(address(vault)), 8e8);
    }

    // ================================================================ atomicity

    function test_basket_is_atomic_one_component_refuses_nothing_trades() public {
        _fund();
        _skew();
        oracle.set(address(b), 50e8, ISessionOracle.Session.CLOSED, ISessionOracle.Cause.EARLY_CLOSE);
        uint256 aBefore = a.balanceOf(address(vault));
        uint256 bBefore = b.balanceOf(address(vault));
        vm.prank(user);
        vm.expectRevert();
        vault.rebalance(_rebalanceSwaps());
        assertEq(a.balanceOf(address(vault)), aBefore);
        assertEq(b.balanceOf(address(vault)), bBefore);
    }

    function test_impact_cap_exceeded_rolls_back_whole_batch() public {
        // a large vault: sell $6,000 of A (cap is $5,000)
        a.mint(address(vault), 100e8); // $10,000
        b.mint(address(vault), 100e8); // $5,000 -> 67/33, drift above threshold
        bytes[] memory s = new bytes[](2);
        s[0] = _swap(address(b), 1e8, address(a), 0); // harmless first leg
        s[1] = _swap(address(a), 60e8, address(b), 120e8); // $6,000 sold, $6,000 bought
        uint256 aBefore = a.balanceOf(address(vault));

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.ImpactCapExceeded.selector, address(a), 6000e6, CAP));
        vault.rebalance(s);
        assertEq(a.balanceOf(address(vault)), aBefore);

        vm.prank(user);
        assertFalse(vault.tryRebalance(s));
        assertEq(vault.refusalCount(), 1);
        assertEq(a.balanceOf(address(vault)), aBefore, "first leg must be rolled back too");
    }

    function test_slippage_beyond_rule_is_refused_and_recorded() public {
        _fund();
        _skew();
        // sell $300 of A but receive only $270 of B: 10% loss on a 1% rule
        bytes[] memory s = new bytes[](1);
        s[0] = _swap(address(a), 3e8, address(b), 54e7);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.SlippageExceeded.selector, 270e6, 30e6, 2_700_000));
        vault.rebalance(s);
        vm.prank(user);
        assertFalse(vault.tryRebalance(s));
        assertEq(vault.refusalCount(), 1);
    }

    function test_no_drain_path_through_router_calldata() public {
        _fund();
        _skew();
        // calldata that sends the output to the attacker instead of the vault
        bytes[] memory s = new bytes[](1);
        s[0] = abi.encodeCall(MockRouter.swap, (address(a), 3e8, address(b), 6e8, attacker));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.SlippageExceeded.selector, 0, 300e6, 0));
        vault.rebalance(s);
        assertEq(b.balanceOf(attacker), 0);
        assertEq(a.allowance(address(vault), address(router)), 0, "approvals are reset");
    }

    function test_approvals_are_zero_after_trading() public {
        _fund();
        assertEq(usdc.allowance(address(vault), address(router)), 0);
        assertEq(a.allowance(address(vault), address(router)), 0);
    }

    function test_deposit_with_swaps_is_gated() public {
        oracle.set(address(b), 50e8, ISessionOracle.Session.CLOSED, ISessionOracle.Cause.WEEKEND);
        bytes[] memory s = new bytes[](1);
        s[0] = _swap(address(usdc), 500e6, address(a), 5e8);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.MarketClosed.selector, address(b), ISessionOracle.Cause.WEEKEND));
        vault.deposit(500e6, s);
        assertEq(usdc.balanceOf(address(vault)), 0);
    }

    // ================================================================ escape hatch

    function test_withdraw_works_when_everything_is_broken() public {
        _fund();
        oracle.setReverts(true);
        router.setReverts(true);
        oracle.set(address(a), 0, ISessionOracle.Session.UNKNOWN, ISessionOracle.Cause.FEED_INVALID);
        vm.prank(user);
        vault.withdrawAllInKind(user);
        assertEq(a.balanceOf(address(vault)), 0);
        assertEq(b.balanceOf(address(vault)), 0);
        assertEq(a.balanceOf(user), 5e8);
        assertEq(b.balanceOf(user), 10e8);
    }

    function test_withdraw_all_skips_a_failing_token_without_blocking_others() public {
        _fund();
        usdc.mint(address(vault), 7e6);
        a.setBlocked(user, true);
        vm.prank(user);
        vault.withdrawAllInKind(user);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(b.balanceOf(user), 10e8);
        assertEq(a.balanceOf(address(vault)), 5e8); // stuck token still individually addressable
        a.setBlocked(user, false);
        vm.prank(user);
        vault.withdraw(address(a), 5e8, user);
        assertEq(a.balanceOf(user), 5e8);
    }

    function test_depositInKind_needs_no_oracle() public {
        oracle.setReverts(true);
        a.mint(user, 3e8);
        vm.startPrank(user);
        a.approve(address(vault), 3e8);
        address[] memory t = new address[](1);
        t[0] = address(a);
        uint256[] memory amt = new uint256[](1);
        amt[0] = 3e8;
        vault.depositInKind(t, amt);
        vm.stopPrank();
        assertEq(a.balanceOf(address(vault)), 3e8);
    }

    // ================================================================ ownership

    function testFuzz_only_owner(address who) public {
        vm.assume(who != user);
        IIndexVault.Component[] memory c = new IIndexVault.Component[](1);
        c[0] = IIndexVault.Component(address(a), 10_000);
        bytes[] memory none = new bytes[](0);
        address[] memory t = new address[](0);
        uint256[] memory amt = new uint256[](0);
        vm.startPrank(who);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.rebalance(none);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.tryRebalance(none);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.deposit(1, none);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.depositInKind(t, amt);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.withdraw(address(a), 1, who);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.withdrawAllInKind(who);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.setComponents(c);
        vm.expectRevert(IIndexVault.NotOwner.selector);
        vault.setRules(IIndexVault.Rules(1, 1, 1));
        vm.expectRevert(IIndexVault.NotSelf.selector);
        vault.executeTrade(none);
        vm.stopPrank();
    }

    function test_initialize_only_once_and_implementation_is_locked() public {
        vm.expectRevert(IIndexVault.AlreadyInitialized.selector);
        vault.initialize(attacker);
        IndexVault impl = IndexVault(factory.implementation());
        vm.expectRevert(IIndexVault.AlreadyInitialized.selector);
        impl.initialize(attacker);
    }

    // ================================================================ configuration

    function testFuzz_weights_must_sum_to_10000(uint8 nRaw, uint256 seed) public {
        uint256 n = bound(nRaw, 1, 2); // only two allowed tokens exist; the 1..20 range is covered below
        IIndexVault.Component[] memory c = new IIndexVault.Component[](n);
        uint256 sum;
        for (uint256 i; i < n; ++i) {
            uint16 w = uint16(uint256(keccak256(abi.encode(seed, i))) % 10_001);
            c[i] = IIndexVault.Component(i == 0 ? address(a) : address(b), w);
            sum += w;
        }
        vm.prank(user);
        if (sum != 10_000) vm.expectRevert(IIndexVault.WeightsMustSumTo10000.selector);
        vault.setComponents(c);
    }

    function test_twenty_components_ok_twentyone_rejected() public {
        address[] memory toks = new address[](21);
        uint256[] memory caps = new uint256[](21);
        for (uint256 i; i < 21; ++i) {
            toks[i] = address(new MockToken("T", 8));
            caps[i] = CAP;
        }
        IndexVaultFactory f = new IndexVaultFactory(oracle, address(usdc), address(router), 1 hours, toks, caps);
        vm.prank(user);
        IndexVault v = IndexVault(f.createVault());
        IIndexVault.Component[] memory c = new IIndexVault.Component[](20);
        for (uint256 i; i < 20; ++i) c[i] = IIndexVault.Component(toks[i], 500);
        vm.prank(user);
        v.setComponents(c);
        IIndexVault.Component[] memory c21 = new IIndexVault.Component[](21);
        for (uint256 i; i < 21; ++i) c21[i] = IIndexVault.Component(toks[i], 0);
        vm.prank(user);
        vm.expectRevert(IIndexVault.BadComponents.selector);
        v.setComponents(c21);
    }

    function test_unlisted_token_and_duplicates_rejected() public {
        MockToken other = new MockToken("X", 8);
        IIndexVault.Component[] memory c = new IIndexVault.Component[](1);
        c[0] = IIndexVault.Component(address(other), 10_000);
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.TokenNotAllowed.selector, address(other)));
        vault.setComponents(c);

        IIndexVault.Component[] memory d = new IIndexVault.Component[](2);
        d[0] = IIndexVault.Component(address(a), 5000);
        d[1] = IIndexVault.Component(address(a), 5000);
        vm.prank(user);
        vm.expectRevert(IIndexVault.BadComponents.selector);
        vault.setComponents(d);
    }

    function test_slippage_rule_capped_at_500() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(IIndexVault.SlippageCapExceeded.selector, uint16(501)));
        vault.setRules(IIndexVault.Rules(500, 0, 501));
    }

    // ================================================================ factory

    function test_factory_registry_and_immutability() public {
        assertEq(factory.vaultsOf(user).length, 1);
        assertEq(factory.vaultCount(), 1);
        assertEq(factory.allVaults(0, 10)[0], address(vault));
        assertEq(factory.capOf(address(a)), CAP);
        assertEq(vault.owner(), user);
        assertEq(address(vault.factory()), address(factory));
    }

    function test_calldata_suffix_is_inert_on_vault() public {
        _fund();
        _skew();
        bytes memory data = abi.encodeCall(IIndexVault.tryRebalance, (_rebalanceSwaps()));
        bytes memory suffixed = bytes.concat(data, hex"62635f6f72675f636f646500000b0080218021802180218021802180218021");
        vm.prank(user);
        (bool ok, bytes memory ret) = address(vault).call(suffixed);
        assertTrue(ok);
        assertTrue(abi.decode(ret, (bool)));
    }
}
