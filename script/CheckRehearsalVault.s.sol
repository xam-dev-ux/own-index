// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {IndexVault} from "../src/IndexVault.sol";

interface IBal {
    function balanceOf(address) external view returns (uint256);
}

/// @notice Read-only. Run it with `--rpc-url` (no `--broadcast`, no keystore) against the chain after RehearseSepoliaVault.
/// It reads the DEPLOYED contracts, never a simulation, which is the whole point (a script that checks its own simulated
/// state proves nothing about the chain). Environment: ORACLE, FACTORY, VAULT, VAULT_OUT.
contract CheckRehearsalVault is Script {
    address constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;
    uint256 bad;

    function run() external {
        require(block.chainid != 8453, "REHEARSAL: never on mainnet");
        ISessionOracle oracle = ISessionOracle(vm.envAddress("ORACLE"));
        IndexVaultFactory f = IndexVaultFactory(vm.envAddress("FACTORY"));
        IndexVault v = IndexVault(vm.envAddress("VAULT"));
        IndexVault vo = IndexVault(vm.envAddress("VAULT_OUT"));

        _is("factory points at the oracle", address(f.oracle()) == address(oracle));
        _is("factory has two vaults", f.vaultCount() == 2);
        address[] memory mine = f.vaultsOf(DEPLOYER);
        _is("both vaults are listed under the deployer", mine.length == 2 && mine[0] == address(v) && mine[1] == address(vo));
        _is("vault 1 is owned by the deployer", v.owner() == DEPLOYER);
        _is("vault 2 is owned by the deployer", vo.owner() == DEPLOYER);

        IIndexVault.Component[] memory c = v.components();
        _is("vault 1 has four components", c.length == 4);
        for (uint256 i; i < c.length; ++i) {
            ISessionOracle.Mark memory m = oracle.markOf(c[i].token);
            // FRESH needs the feed print to be recent; the demo threshold is 12h, so this is time-limited by design.
            _is("component is FRESH on the chain's oracle", m.session == ISessionOracle.Session.FRESH);
            _is("vault holds its component", IBal(c[i].token).balanceOf(address(v)) == 1e8);
            _is("factory cap is set", f.capOf(c[i].token) == 10_000e6);
        }
        _is("vault 1 recorded two refusals (NO_DRIFT, FEED_FAULT)", v.refusalCount() == 2);
        _is("vault 1 never rebalanced", v.rebalanceCount() == 0);
        _is("vault 2 withdrew everything in kind", IBal(c[0].token).balanceOf(address(vo)) == 0);
        _is("deployer got the withdrawn token back", IBal(c[0].token).balanceOf(DEPLOYER) == 1e8);

        if (bad == 0) console.log("ALL MATCH");
        else {
            console.log("DIVERGENCE, mismatches:", bad);
            revert("rehearsal does not match the chain");
        }
    }

    function _is(string memory what, bool ok) internal {
        console.log(ok ? "ok     " : "MISMATCH", what);
        if (!ok) bad++;
    }
}
