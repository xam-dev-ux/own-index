// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";

/// @dev Stand-in for the vault's shapes: dynamic arrays of addresses, amounts, bytes and structs.
contract DynTarget {
    struct Component {
        address token;
        uint16 weight;
    }

    function rebalance(address[] calldata tokens, uint256[] calldata amounts, bytes[] calldata swaps)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(tokens, amounts, swaps));
    }

    function setComponents(Component[] calldata c, uint32 x) external pure returns (bytes32) {
        return keccak256(abi.encode(c, x));
    }

    function memoryDecode(bytes[] memory swaps) external pure returns (bytes32) {
        return keccak256(abi.encode(swaps));
    }
}

/// @dev Forwards calldata verbatim by delegatecall, as a minimal proxy does.
contract Forwarder {
    address immutable impl;

    constructor(address i) {
        impl = i;
    }

    fallback() external {
        address i = impl;
        assembly {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), i, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

contract CalldataSuffixTest is Test {
    DynTarget t;
    Forwarder fwd;
    bytes constant ERC8021 = hex"07626173656170700080218021802180218021802180218021";

    function setUp() public {
        t = new DynTarget();
        fwd = new Forwarder(address(t));
    }

    function _args() internal pure returns (bytes memory) {
        address[] memory a = new address[](3);
        a[0] = address(1);
        a[1] = address(2);
        a[2] = address(3);
        uint256[] memory n = new uint256[](3);
        n[0] = 1e8;
        n[1] = 2e8;
        n[2] = 3e8;
        bytes[] memory b = new bytes[](3);
        b[0] = hex"aa";
        b[1] = hex"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        b[2] = hex"";
        return abi.encodeCall(DynTarget.rebalance, (a, n, b));
    }

    function _same(address target, bytes memory data, bytes memory suffix) internal {
        (bool ok1, bytes memory r1) = target.staticcall(data);
        (bool ok2, bytes memory r2) = target.staticcall(bytes.concat(data, suffix));
        assertTrue(ok1);
        assertTrue(ok2, "suffix broke decoding");
        assertEq(keccak256(r1), keccak256(r2));
    }

    function test_dynamic_arrays_with_suffix_direct() public {
        _same(address(t), _args(), ERC8021);
    }

    function test_dynamic_arrays_with_suffix_through_proxy() public {
        _same(address(fwd), _args(), ERC8021);
    }

    function test_struct_array_with_suffix() public {
        DynTarget.Component[] memory c = new DynTarget.Component[](2);
        c[0] = DynTarget.Component(address(1), 6000);
        c[1] = DynTarget.Component(address(2), 4000);
        bytes memory data = abi.encodeCall(DynTarget.setComponents, (c, 7));
        _same(address(t), data, ERC8021);
        _same(address(fwd), data, ERC8021);
    }

    function test_memory_decode_with_suffix() public {
        bytes[] memory b = new bytes[](2);
        b[0] = hex"01";
        b[1] = hex"0202";
        _same(address(t), abi.encodeCall(DynTarget.memoryDecode, (b)), ERC8021);
    }

    /// @dev Any suffix, any length, including ones that look like ABI words.
    function testFuzz_any_suffix(bytes calldata suffix) public {
        _same(address(t), _args(), suffix);
        _same(address(fwd), _args(), suffix);
    }
}
