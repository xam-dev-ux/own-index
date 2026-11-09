// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ISessionOracle} from "../src/ISessionOracle.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {MockToken, MockRouter, MockOracle} from "../src/testing/MockTrade.sol";

interface IB20 {
    function decimals() external view returns (uint8);
    function uiMultiplier() external view returns (uint256);
    function newUIMultiplier() external view returns (uint256);
    function effectiveAt() external view returns (uint256);
    function toUIAmount(uint256) external view returns (uint256);
}

/// @notice Mainnet fork. B20 tokens are precompiles and run natively under base-forge, so these reads hit the real
/// implementation. Verifies the multiplier model IndexVault is built on, at the pinned block.
contract IndexVaultForkTest is Test {
    string[10] internal ADDR = [
        "0xb200000000000000000000C2e324d24d7eEcd1fb", // AAPL
        "0xb200000000000000000000d9192b6B456483C2E8", // AMZN
        "0xb2000000000000000000002D0BA3164cc74f58B7", // GOOGL
        "0xb2000000000000000000008bC8786B856E61707C", // META
        "0xB200000000000000000000Ab99cFa739E253872B", // MSFT
        "0xb2000000000000000000004884b426556b92883d", // MSTR
        "0xb20000000000000000000078ee7ce2fE4908108C", // NVDA
        "0xb200000000000000000000397293Cb8cda9a10c5", // SNDK
        "0xb2000000000000000000007b9fcbd005511aCBd5", // SPCX
        "0xb2000000000000000000001e800a7f5189430cD0"  // TSLA
    ];

    function setUp() public {
        if (block.chainid != 8453) vm.skip(true);
    }

    function _tok(uint256 i) internal view returns (address) {
        return vm.parseAddress(ADDR[i]);
    }

    function test_multiplier_model_matches_live_b20() public view {
        for (uint256 i; i < 10; ++i) {
            IB20 t = IB20(_tok(i));
            uint256 m = t.uiMultiplier();
            uint256 pendingAt = t.effectiveAt();
            console.log(i, m, pendingAt);
            assertEq(t.decimals(), 8);
            assertGe(m, 0.5e18, "multiplier is WAD-scaled");
            assertLe(m, 10e18, "multiplier is WAD-scaled");
            // effectiveAt: 0 = nothing pending, else a unix timestamp in seconds (not ms, not a block number)
            assertTrue(pendingAt == 0 || (pendingAt > 1.6e9 && pendingAt < 1e11), "effectiveAt unit");
            assertApproxEqAbs(t.toUIAmount(1e8), 1e8 * m / 1e18, 1);
        }
    }

    function test_vault_multiplier_refusal_against_real_tokens() public {
        MockOracle oracle = new MockOracle();
        MockToken usdc = new MockToken("USDC", 6);
        address[] memory toks = new address[](2);
        toks[0] = _tok(0); // AAPL
        toks[1] = _tok(9); // TSLA
        uint256[] memory caps = new uint256[](2);
        caps[0] = 50_000e6;
        caps[1] = 50_000e6;
        oracle.fresh(toks[0], 200e8);
        oracle.fresh(toks[1], 300e8);
        IndexVaultFactory f =
            new IndexVaultFactory(oracle, address(usdc), address(new MockRouter()), 1 hours, toks, caps);
        IndexVault v = IndexVault(f.createVault());
        IIndexVault.Component[] memory c = new IIndexVault.Component[](2);
        c[0] = IIndexVault.Component(toks[0], 5000);
        c[1] = IIndexVault.Component(toks[1], 5000);
        v.setComponents(c);

        // real state: nothing pending -> the only refusal is NO_DRIFT (empty vault), via real decimals() reads
        (, IIndexVault.Refusal[] memory rs,,) = v.rebalanceStatus();
        assertEq(rs.length, 1);
        assertEq(uint8(rs[0].kind), uint8(IIndexVault.RefusalKind.NO_DRIFT));

        bytes4 sel = IB20.effectiveAt.selector;
        vm.mockCall(toks[0], abi.encodeWithSelector(sel), abi.encode(block.timestamp + 10 minutes));
        (, rs,,) = v.rebalanceStatus();
        assertEq(uint8(rs[0].kind), uint8(IIndexVault.RefusalKind.MULTIPLIER_CHANGE_IMMINENT));
        assertEq(rs[0].token, toks[0]);

        vm.mockCall(toks[0], abi.encodeWithSelector(sel), abi.encode(block.timestamp + 2 hours));
        (, rs,,) = v.rebalanceStatus();
        assertEq(uint8(rs[0].kind), uint8(IIndexVault.RefusalKind.NO_DRIFT));
    }
}
