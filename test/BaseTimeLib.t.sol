// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BaseTimeLib} from "../src/BaseTimeLib.sol";
import {MockBaseTime, RevertingBaseTime, ShortReturnBaseTime} from "./mocks/MockBaseTime.sol";

contract LibHarness {
    function isActive() external view returns (bool) {
        return BaseTimeLib.isActive();
    }

    function timestampMs() external view returns (uint256) {
        return BaseTimeLib.timestampMs();
    }

    function millisPart() external view returns (uint16) {
        return BaseTimeLib.millisPart();
    }

    function slotIndex() external view returns (uint8) {
        return BaseTimeLib.slotIndex();
    }
}

/// @dev Unit tests against a mock. They prove the library's logic, not the live predeploy;
/// see test/fork/DenimLive.t.sol for that.
contract BaseTimeLibTest is Test {
    address constant PREDEPLOY = 0x4200000000000000000000000000000000000030;
    LibHarness h;

    function setUp() public {
        h = new LibHarness();
        vm.warp(1_000_000);
    }

    function _etchMock() internal returns (MockBaseTime m) {
        vm.etch(PREDEPLOY, address(new MockBaseTime()).code);
        m = MockBaseTime(PREDEPLOY);
    }

    function test_inactive_whenNothingEtched() public view {
        assertFalse(h.isActive());
    }

    function test_inactive_whenCallsRevert() public {
        vm.etch(PREDEPLOY, address(new RevertingBaseTime()).code);
        assertFalse(h.isActive());
        assertEq(h.millisPart(), 0);
        assertEq(h.slotIndex(), 0);
        assertEq(h.timestampMs(), block.timestamp * 1000);
    }

    function test_inactive_whenReturnDataTooShort() public {
        vm.etch(PREDEPLOY, address(new ShortReturnBaseTime()).code);
        assertFalse(h.isActive());
        assertEq(h.timestampMs(), block.timestamp * 1000);
    }

    function test_active_withWorkingMock() public {
        _etchMock();
        assertTrue(h.isActive());
    }

    function test_timestampMs_fallsBackWhenInactive() public view {
        assertEq(h.timestampMs(), block.timestamp * 1000);
    }

    function test_timestampMs_usesPredeployWhenActive() public {
        MockBaseTime m = _etchMock();
        m.setMillisPart(600);
        assertEq(h.timestampMs(), 1_000_000 * 1000 + 600);
        m.setTimestampMs(42);
        assertEq(h.timestampMs(), 42);
    }

    function test_millisPart_zeroWhenInactive() public view {
        assertEq(h.millisPart(), 0);
    }

    function test_slotIndex_mapsFiveValidParts() public {
        MockBaseTime m = _etchMock();
        for (uint16 i = 0; i < 5; i++) {
            m.setMillisPart(i * 200);
            assertEq(h.millisPart(), i * 200);
            assertEq(h.slotIndex(), i);
        }
    }

    /// Invalid parts (not one of 0/200/400/600/800) are treated as an unavailable
    /// predeploy: inactive, part 0, whole-second fallback. Valid parts map to 0..4.
    function testFuzz_millisPart_allUint16(uint16 part) public {
        MockBaseTime m = _etchMock();
        m.setMillisPart(part);
        bool valid = part < 1000 && part % 200 == 0;
        assertEq(h.isActive(), valid);
        assertLe(h.slotIndex(), 4);
        if (valid) {
            assertEq(h.slotIndex(), part / 200);
            assertEq(h.millisPart(), part);
        } else {
            assertEq(h.slotIndex(), 0);
            assertEq(h.millisPart(), 0);
            assertEq(h.timestampMs(), block.timestamp * 1000);
        }
    }
}
