// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Script.sol";
import {MainnetConfig} from "./MainnetConfig.sol";
import {SessionOracle} from "../src/SessionOracle.sol";
import {SlipstreamAdapter} from "../src/SlipstreamAdapter.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";

interface IFeedMeta {
    function description() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @notice Reads the deployed contracts FROM THE CHAIN and fails unless every value equals what the environment and
/// MainnetConfig say it should be. Run with `--rpc-url` and no `--broadcast`: nothing is sent, no key is needed.
/// Addresses come from ORACLE_ADDRESS, ADAPTER_ADDRESS, FACTORY_ADDRESS. A failed `require` fails the script.
contract VerifyMainnet is MainnetConfig {
    function run() external view {
        Stock[12] memory u = _universe();
        OracleParams memory p = _params(u);
        SessionOracle o = SessionOracle(vm.envAddress("ORACLE_ADDRESS"));
        SlipstreamAdapter a = SlipstreamAdapter(vm.envAddress("ADAPTER_ADDRESS"));
        IndexVaultFactory f = IndexVaultFactory(vm.envAddress("FACTORY_ADDRESS"));

        // --- oracle
        require(o.RECORDER() == DEPLOYER, "oracle: recorder");
        require(o.weekOpenOffset() == p.openOffset && o.weekCloseOffset() == p.closeOffset, "oracle: window");
        require(o.heartbeatSecs() == p.heartbeat && o.heartbeatMarginSecs() == p.heartbeatMargin, "oracle: heartbeat");
        require(o.comparisonWindowSecs() == p.comparisonWindow, "oracle: comparison window");
        require(o.registry() == REGISTRY, "oracle: registry");
        require(o.confirmedUntil() == p.confirmedUntil, "oracle: calendar confirmation");
        require(o.tokenCount() == 12, "oracle: token count");
        require(o.closureCount() == p.closureStart.length, "oracle: closure count");
        for (uint256 i; i < p.closureStart.length; ++i) {
            SessionOracle.Closure memory c = o.closureAt(i);
            require(c.start == p.closureStart[i] && c.end == p.closureEnd[i] && uint8(c.kind) == p.closureKind[i], "oracle: closure");
        }
        for (uint256 i; i < 12; ++i) {
            (address feed, address sec, uint32 thr,,, bool active) = o.configOf(u[i].token);
            require(active && feed == u[i].feed && sec == u[i].secondaryFeed && thr == p.thresholds[i], string.concat("oracle: config ", u[i].symbol));
            require(keccak256(bytes(IFeedMeta(feed).description())) == keccak256(bytes(string.concat("Coinbase ", u[i].symbol))), string.concat("oracle: feed description ", u[i].symbol));
            if (sec != address(0)) {
                require(keccak256(bytes(IFeedMeta(sec).description())) == keccak256(bytes(u[i].secondaryDescription)), string.concat("oracle: secondary description ", u[i].symbol));
            }
            ISessionOracle.Mark memory m = o.markOf(u[i].token);
            // CALENDAR_NOT_LOADED / NOT_CONFIGURED here would mean the post-deploy configuration did not take effect
            require(m.cause != ISessionOracle.Cause.CALENDAR_NOT_LOADED && m.cause != ISessionOracle.Cause.NOT_CONFIGURED, string.concat("oracle: verdict cause ", u[i].symbol));
            require(m.session != ISessionOracle.Session.UNKNOWN, string.concat("oracle: verdict unknown ", u[i].symbol));
            console.log(u[i].symbol, uint256(m.session), uint256(m.cause));
        }

        // --- adapter
        require(address(a.router()) == SLIPSTREAM_ROUTER && a.usdc() == USDC, "adapter: router/usdc");
        require(a.listedTokens().length == 12, "adapter: listed");
        for (uint256 i; i < 12; ++i) require(a.poolOf(u[i].token) == u[i].pool, string.concat("adapter: pool ", u[i].symbol));

        // --- factory
        require(address(f.oracle()) == address(o), "factory: oracle");
        require(f.usdc() == USDC && f.router() == address(a), "factory: usdc/router");
        require(f.multiplierWindowSecs() == p.multiplierWindow, "factory: multiplier window");
        require(f.allowedTokens().length == 12, "factory: allowed");
        for (uint256 i; i < 12; ++i) require(f.capOf(u[i].token) == u[i].cap, string.concat("factory: cap ", u[i].symbol));
        require(f.implementation().code.length > 0, "factory: implementation");
        require(address(IndexVault(f.implementation()).factory()) == address(1), "factory: implementation must be locked");
        console.log("ALL ON-CHAIN CHECKS MATCHED");
    }
}
