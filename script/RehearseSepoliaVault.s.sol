// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {SlipstreamAdapter, ISlipstreamSwapRouter} from "../src/SlipstreamAdapter.sol";
import {MockFeed, MockRegistry} from "../src/testing/MockFeed.sol";
import {MockToken, MockSlipstream} from "../src/testing/MockTrade.sol";

/// @notice SEPOLIA REHEARSAL ONLY (second one: the vault side). Run with `--account speedrun`; the keystore password is
/// typed at runtime. Refuses to run on chain 8453.
///
/// WHAT THIS VALIDATES: the real deployment flow for the contracts the first rehearsal did not touch. Oracle, then
/// adapter, then factory (which clones the vault implementation), then a vault created, configured, funded through the
/// adapter, refused on chain, and emptied in kind.
/// WHAT IT DOES NOT VALIDATE: anything about real liquidity, real pools, real feeds, real windows or real caps.
/// The "pools" are a mock router that swaps 1:1 in raw units: with 6-decimal USDC, 8-decimal tokens and a $100 mock
/// price that is exactly the oracle price, so the batch slippage check sees a clean trade. Price impact is not tested.
///
/// DISPOSABLE: every number, token, feed and "pool" below. None of it may be carried to mainnet.
/// As with the first rehearsal, the checks inside this script read simulated state. The rehearsal is only done when
/// CheckRehearsalVault, run against the chain with the printed addresses, says ALL MATCH.
contract RehearseSepoliaVault is Script {
    address constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;
    uint256 constant N = 4;

    // Outputs, kept in storage so the log at the end does not need a stack of locals.
    SessionOracle oracle;
    MockToken usdc;
    MockSlipstream ss;
    SlipstreamAdapter adapter;
    IndexVaultFactory factory;
    IIndexVault vault;
    IIndexVault vaultOut;
    MockToken[N] tok;
    MockFeed[N] feed;

    function run() external {
        require(block.chainid != 8453, "REHEARSAL: never on mainnet");
        uint256 t = block.timestamp;

        vm.startBroadcast(DEPLOYER);
        _oracleAndTokens(t);
        _adapterAndFactory();
        _vaultFlow(t);
        vm.stopBroadcast();

        console.log("oracle     ", address(oracle));
        console.log("adapter    ", address(adapter));
        console.log("factory    ", address(factory));
        console.log("vault      ", address(vault));
        console.log("vaultOut   ", address(vaultOut));
        console.log("usdc (mock)", address(usdc));
        console.log("Disposable parameters. Now run CheckRehearsalVault against the chain.");
    }

    function _oracleAndTokens(uint256 t) internal {
        // DISPOSABLE: the window is the whole week, so the rehearsal works whenever it is run.
        oracle = new SessionOracle(DEPLOYER, 0, 7 days, 24 hours, 1 hours, 10 minutes);
        oracle.confirmCalendarUntil(uint64(t + 30 days));
        oracle.setRegistry(address(new MockRegistry()));
        usdc = new MockToken("USDC", 6);
        string[N] memory names = ["MOCKA", "MOCKB", "MOCKC", "MOCKD"];
        for (uint256 i; i < N; ++i) {
            tok[i] = new MockToken(names[i], 8);
            feed[i] = new MockFeed();
            feed[i].set(100e8, t - 60); // $100, fresh
            // DISPOSABLE threshold: long enough that the demo stays FRESH for about half a day.
            oracle.configureToken(address(tok[i]), address(feed[i]), address(0), 12 hours);
        }
    }

    function _adapterAndFactory() internal {
        ss = new MockSlipstream();
        address[] memory toks = new address[](N);
        address[] memory pools = new address[](N);
        uint256[] memory caps = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            toks[i] = address(tok[i]);
            pools[i] = address(uint160(0xB000 + i)); // DISPOSABLE: placeholder pool addresses, the mock only compares them
            ss.setPool(address(usdc), toks[i], 10, pools[i]);
            caps[i] = 10_000e6; // DISPOSABLE
            tok[i].mint(address(ss), 1e15); // inventory the mock router pays out of
        }
        usdc.mint(address(ss), 1e15);
        adapter = new SlipstreamAdapter(ISlipstreamSwapRouter(address(ss)), address(usdc), toks, pools);
        factory = new IndexVaultFactory(ISessionOracle(address(oracle)), address(usdc), address(adapter), 1 hours, toks, caps);
        usdc.mint(DEPLOYER, 10_000e6);
    }

    function _vaultFlow(uint256 t) internal {
        // --- vault 1: four equal components, funded through the adapter, then two recorded refusals
        vault = IIndexVault(factory.createVault());
        IIndexVault.Component[] memory comps = new IIndexVault.Component[](N);
        bytes[] memory legs = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            comps[i] = IIndexVault.Component(address(tok[i]), 2500);
            legs[i] = abi.encodeCall(SlipstreamAdapter.buy, (address(tok[i]), 100e6, 0));
        }
        vault.setComponents(comps);
        vault.setRules(IIndexVault.Rules({driftThresholdBps: 500, minRebalanceInterval: 0, maxSlippageBps: 200}));
        usdc.approve(address(vault), N * 100e6);
        vault.deposit(N * 100e6, legs);

        // Refusal 1: nothing drifted -> NO_DRIFT.
        require(!vault.tryRebalance(new bytes[](0)), "expected NO_DRIFT");
        // Refusal 2: one feed goes silent past its threshold -> FEED_FAULT. Then the feed is put back.
        feed[3].set(100e8, t - 13 hours);
        require(!vault.tryRebalance(new bytes[](0)), "expected FEED_FAULT");
        feed[3].set(100e8, t - 60);

        // --- vault 2: one component, in and out, to prove an unconditional withdrawal
        vaultOut = IIndexVault(factory.createVault());
        IIndexVault.Component[] memory one = new IIndexVault.Component[](1);
        one[0] = IIndexVault.Component(address(tok[0]), 10_000);
        vaultOut.setComponents(one);
        bytes[] memory leg = new bytes[](1);
        leg[0] = abi.encodeCall(SlipstreamAdapter.buy, (address(tok[0]), 100e6, 0));
        usdc.approve(address(vaultOut), 100e6);
        vaultOut.deposit(100e6, leg);
        vaultOut.withdrawAllInKind(DEPLOYER);
    }
}
