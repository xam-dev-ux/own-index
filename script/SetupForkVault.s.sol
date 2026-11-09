// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Script.sol";
import {MainnetConfig} from "./MainnetConfig.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {SlipstreamAdapter} from "../src/SlipstreamAdapter.sol";

interface IERC20Min {
    function approve(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

/// @notice LOCAL FORK ONLY (scripts/setup_fork.sh). Creates a vault with all 10 components, deposits through the
/// real Slipstream pools and records one real refusal (NO_DRIFT) so a UI has live state to read.
/// Owner is anvil's first dev account (public, worthless on a real chain). Refuses to run anywhere but a fork
/// whose chain id is 8453 AND whose factory is the one passed in the environment.
contract SetupForkVault is MainnetConfig {
    address constant OWNER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    function run() external {
        require(block.chainid == 8453, "fork only");
        IndexVaultFactory f = IndexVaultFactory(vm.envAddress("FACTORY_ADDRESS"));
        Stock[10] memory u = _universe();

        uint256 n = N;
        IIndexVault.Component[] memory comps = new IIndexVault.Component[](n);
        bytes[] memory legs = new bytes[](n);
        uint16 left = 10_000;
        for (uint256 i; i < n; ++i) {
            uint16 w = i == n - 1 ? left : 1000;
            left -= w;
            comps[i] = IIndexVault.Component(u[i].token, w);
            legs[i] = abi.encodeCall(SlipstreamAdapter.buy, (u[i].token, 800e6, 0));
        }

        vm.startBroadcast(OWNER);
        IIndexVault v = IIndexVault(f.createVault());
        v.setComponents(comps);
        v.setRules(IIndexVault.Rules({driftThresholdBps: 500, minRebalanceInterval: 0, maxSlippageBps: 200}));
        IERC20Min(USDC).approve(address(v), 8_000e6);
        v.deposit(8_000e6, legs);
        // Nothing has drifted yet: a real, recorded refusal while the market is open.
        bool executed = v.tryRebalance(new bytes[](0));
        vm.stopBroadcast();

        require(!executed, "expected a NO_DRIFT refusal");
        console.log("Vault", address(v));
    }
}
