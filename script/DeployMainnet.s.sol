// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Script.sol";
import {MainnetConfig} from "./MainnetConfig.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {SlipstreamAdapter, ISlipstreamSwapRouter} from "../src/SlipstreamAdapter.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";

/// @notice MAINNET deployment: SessionOracle, SlipstreamAdapter, IndexVaultFactory, in that order, plus all the
/// post-deploy configuration of the oracle. Run with `--account speedrun`; the keystore password is typed at runtime.
///
/// Nothing here is a measurement. Window offsets, thresholds, closures and windows come from the environment
/// (deploy/mainnet.params.env) and the script REFUSES to run while any of them is missing or still says
/// PENDING / DISPOSABLE. Use `make deploy-mainnet-dry` first: it runs this same script as a simulation.
///
/// Reading state at the end of this script reads the SIMULATION, not the chain. The check that counts is
/// `make verify-mainnet`, which reads the deployed contracts from the chain (VerifyMainnet.s.sol).
///
/// No vault is created here, and the deployer owns nothing except the oracle's recorder permission (snapshot
/// configuration; it touches no funds). The multiplier baseline of a vault is set when its owner calls
/// `setComponents`, so there is no global "initial observation" to perform at deploy time.
contract DeployMainnet is MainnetConfig {
    function run() external {
        Stock[10] memory u = _universe();
        OracleParams memory p = _params(u); // reverts on any placeholder

        vm.startBroadcast(DEPLOYER);

        // 1. oracle, then everything that is not a constructor argument
        SessionOracle oracle = new SessionOracle(
            DEPLOYER, p.openOffset, p.closeOffset, p.heartbeat, p.heartbeatMargin, p.comparisonWindow
        );
        oracle.setRegistry(REGISTRY);
        for (uint256 i; i < N; ++i) {
            oracle.configureToken(u[i].token, u[i].feed, u[i].secondaryFeed, p.thresholds[i]);
        }
        for (uint256 i; i < p.closureStart.length; ++i) {
            oracle.addClosure(p.closureStart[i], p.closureEnd[i], SessionOracle.ClosureKind(p.closureKind[i]));
        }
        oracle.confirmCalendarUntil(p.confirmedUntil);

        // 2. adapter over the measured pools (its constructor refuses any other pool)
        address[] memory toks = new address[](N);
        address[] memory pools = new address[](N);
        uint256[] memory caps = new uint256[](N);
        for (uint256 i; i < N; ++i) {
            toks[i] = u[i].token;
            pools[i] = u[i].pool;
            caps[i] = u[i].cap;
        }
        SlipstreamAdapter adapter = new SlipstreamAdapter(ISlipstreamSwapRouter(SLIPSTREAM_ROUTER), USDC, toks, pools);

        // 3. factory: immutable oracle, USDC, adapter as router, multiplier window and per-token caps
        IndexVaultFactory factory =
            new IndexVaultFactory(ISessionOracle(address(oracle)), USDC, address(adapter), p.multiplierWindow, toks, caps);

        vm.stopBroadcast();

        // Simulation-side sanity (the real check is verify-mainnet against the chain)
        require(oracle.tokenCount() == N && oracle.closureCount() == p.closureStart.length, "sim: oracle state");
        require(oracle.confirmedUntil() == p.confirmedUntil, "sim: calendar not confirmed");

        console.log("SessionOracle       ", address(oracle));
        console.log("SlipstreamAdapter   ", address(adapter));
        console.log("IndexVaultFactory   ", address(factory));
        console.log("Next: make verify-mainnet ORACLE=<addr> ADAPTER=<addr> FACTORY=<addr>");
    }
}
