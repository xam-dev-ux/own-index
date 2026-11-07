// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {SessionOracle} from "../src/SessionOracle.sol";

/// @notice Deploys SessionOracle. Run with `--account speedrun`; the keystore password is typed at runtime.
/// The window offsets below are provisional until the Sunday reopen has been measured.
contract DeploySessionOracle is Script {
    address constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;
    uint32 constant OPEN_OFFSET = 1 hours; // Monday 01:00 UTC (Sunday 20:00 US Eastern, standard time)
    uint32 constant CLOSE_OFFSET = 5 days + 1 hours; // Saturday 01:00 UTC
    uint32 constant HEARTBEAT = 24 hours;
    uint32 constant HEARTBEAT_MARGIN = 1 hours;
    uint32 constant COMPARISON_WINDOW = 10 minutes;

    function run() external returns (SessionOracle o) {
        vm.startBroadcast(DEPLOYER);
        o = new SessionOracle(DEPLOYER, OPEN_OFFSET, CLOSE_OFFSET, HEARTBEAT, HEARTBEAT_MARGIN, COMPARISON_WINDOW);
        vm.stopBroadcast();
        console.log("SessionOracle", address(o));
    }
}
