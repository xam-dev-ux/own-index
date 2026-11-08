// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IIndexVault} from "../src/IIndexVault.sol";
import {IndexVault} from "../src/IndexVault.sol";
import {IndexVaultFactory} from "../src/IndexVaultFactory.sol";
import {MockOracle, MockToken} from "../src/testing/MockTrade.sol";
import {SlipstreamAdapter, ISlipstreamSwapRouter} from "../src/SlipstreamAdapter.sol";

interface ISlipstreamRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        int24 tickSpacing;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata) external returns (uint256);
    function factory() external view returns (address);
}

interface IClFactory {
    function getPool(address, address, int24) external view returns (address);
}

interface IPool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, bool);
}

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
}

/// @notice Mainnet fork at the pinned block. Real Aero Slipstream router, real pools, real B20 tokens; only the
/// session oracle is a mock (priced at the pool spot), so this tests execution and the vault's balance checks.
contract IndexVaultSlipstreamForkTest is Test {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant ROUTER = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;
    address constant CL_FACTORY = 0x9CB220581b91b0C83223012FE69688b92aD07a76;
    int24 constant TS = 10;

    string[12] internal ADDR = [
        "0xb200000000000000000000C2e324d24d7eEcd1fb",
        "0xb200000000000000000000d9192b6B456483C2E8",
        "0xb2000000000000000000002D0BA3164cc74f58B7",
        "0xb2000000000000000000008bC8786B856E61707C",
        "0xB200000000000000000000Ab99cFa739E253872B",
        "0xb2000000000000000000004884b426556b92883d",
        "0xb20000000000000000000078ee7ce2fE4908108C",
        "0xb200000000000000000000397293Cb8cda9a10c5",
        "0xb2000000000000000000007b9fcbd005511aCBd5",
        "0xb2000000000000000000001e800a7f5189430cD0",
        "0xB2000000000000000000004AFF16039bA04bdFBc", // INTC, index 10
        "0xB20000000000000000000019f6E7C675b73C2e4D" // CRCL, index 11
    ];
    // measured pools from data/impact.json, same order
    string[12] internal POOL = [
        "0xF5FCB9CDAFcE67d50AfEf298F88E709d2B946BA6",
        "0x532e0F46d1e528507FC9454d5847C231f23bDDf6",
        "0x16c70F04C3080a127486Cdf5a4C33c066bBF47C3",
        "0xd072410fa13D242e1d53721Bcf7AF02e3455DC96",
        "0x2740C0faAb738F6e346e545fDE02aEF9B1A01ee7",
        "0x66DCd42E6314B287110922AE36cB2a8bdEECc153",
        "0xF668e21993f0ACd7ab00BB1cFbAeD0df28A3C8EC",
        "0x2836e062a3fe75943a7F4A552E2365b98E414E75",
        "0x880dB7Dda4407D99508574E680d067D1164B3cFE",
        "0x7A33000372f3F028f074182CCb9d16cBEEfBF920",
        "0x3D384288fA79B51De882B06B617aB7989CcAd4f3",
        "0x294666AD6a415E8C33Af801225c04079BB4f1133"
    ];

    MockOracle oracle;
    SlipstreamAdapter adapter;
    IndexVault vault;
    address user = address(0xA11CE);
    address[] toks;

    function setUp() public {
        if (block.chainid != 8453) vm.skip(true);
        oracle = new MockOracle();
        uint256 n = 12;
        address[] memory t = new address[](n);
        uint256[] memory caps = new uint256[](n);
        IIndexVault.Component[] memory c = new IIndexVault.Component[](n);
        for (uint256 i; i < n; ++i) {
            t[i] = vm.parseAddress(ADDR[i]);
            toks.push(t[i]);
            caps[i] = i == 10 ? 5_000e6 : i == 11 ? 10_000e6 : 50_000e6; // docs/vault-design.md
            c[i] = IIndexVault.Component(t[i], i < 8 ? 833 : 834);
            oracle.fresh(t[i], int256(_spotPrice8(vm.parseAddress(POOL[i]))));
        }
        address[] memory pools = new address[](n);
        for (uint256 i; i < n; ++i) pools[i] = vm.parseAddress(POOL[i]);
        // the adapter constructor itself refuses any pool that is not the one in the evidence
        adapter = new SlipstreamAdapter(ISlipstreamSwapRouter(ROUTER), USDC, t, pools);
        IndexVaultFactory f = new IndexVaultFactory(oracle, USDC, address(adapter), 1 hours, t, caps);
        vm.prank(user);
        vault = IndexVault(f.createVault());
        vm.startPrank(user);
        vault.setComponents(c);
        vault.setRules(IIndexVault.Rules({driftThresholdBps: 100, minRebalanceInterval: 0, maxSlippageBps: 100}));
        vm.stopPrank();
        deal(USDC, user, 1_000_000e6);
        vm.prank(user);
        (bool ok,) = USDC.call(abi.encodeWithSignature("approve(address,uint256)", address(vault), type(uint256).max));
        assertTrue(ok);
    }

    /// USD price with 8 decimals of one token (1e8 raw), from the pool spot. USDC is token0 (0x83.. < 0xb2..).
    function _spotPrice8(address pool) internal view returns (uint256) {
        (uint160 sq,,,,,) = IPool(pool).slot0();
        return (uint256(1e10) * 2 ** 96 / uint256(sq)) * 2 ** 96 / uint256(sq);
    }

    function _leg(address token, uint256 usdcIn) internal view returns (bytes memory) {
        return abi.encodeCall(SlipstreamAdapter.buy, (token, usdcIn, 0));
    }

    function test_router_and_measured_pools_correspond() public view {
        assertEq(address(adapter.router()), ROUTER);
        assertEq(adapter.listedTokens().length, 12);
        assertEq(ISlipstreamRouter(ROUTER).factory(), CL_FACTORY);
        for (uint256 i; i < 12; ++i) {
            assertEq(IClFactory(CL_FACTORY).getPool(USDC, toks[i], TS), vm.parseAddress(POOL[i]), "pool differs from evidence");
        }
    }

    function test_legs_the_adapter_does_not_expose_cannot_reach_the_router() public {
        // multi-hop and arbitrary router calldata is not reachable: the vault's only counterparty is the adapter
        bytes[] memory legs = new bytes[](1);
        legs[0] = abi.encodeWithSignature("exactInput((bytes,address,uint256,uint256,uint256))");
        vm.prank(user);
        vm.expectPartialRevert(IIndexVault.SwapFailed.selector);
        vault.deposit(1_000e6, legs);

        // a token that is not in the evidence set is refused by the adapter, so the leg fails
        legs[0] = abi.encodeCall(SlipstreamAdapter.buy, (address(0xBEEF), 1_000e6, 0));
        vm.prank(user);
        vm.expectPartialRevert(IIndexVault.SwapFailed.selector);
        vault.deposit(1_000e6, legs);
    }

    function test_sell_leg_round_trip_through_the_adapter() public {
        bytes[] memory legs = new bytes[](1);
        legs[0] = _leg(toks[0], 800e6);
        vm.prank(user);
        vault.deposit(800e6, legs);
        uint256 bal = IERC20(toks[0]).balanceOf(address(vault));
        bytes[] memory sell = new bytes[](1);
        sell[0] = abi.encodeCall(SlipstreamAdapter.sell, (toks[0], bal, 0));
        vm.prank(user);
        vault.deposit(0, sell); // goes through the same gated, checked path
        assertEq(IERC20(toks[0]).balanceOf(address(vault)), 0);
        assertGe(IERC20(USDC).balanceOf(address(vault)), 800e6 * 99 / 100);
    }

    /// Worst case of the per-leg balance reads: 20 components and 20 legs (12 real pools, then 8 repeated buys).
    function test_gas_20_components_20_legs() public {
        address[] memory t = new address[](20);
        uint256[] memory caps = new uint256[](20);
        IIndexVault.Component[] memory c = new IIndexVault.Component[](20);
        address[] memory pools = new address[](12);
        address[] memory real = new address[](12);
        for (uint256 i; i < 20; ++i) {
            t[i] = i < 12 ? toks[i] : address(new MockToken("PAD", 8));
            caps[i] = 50_000e6;
            c[i] = IIndexVault.Component(t[i], 500);
            oracle.fresh(t[i], i < 12 ? int256(_spotPrice8(vm.parseAddress(POOL[i]))) : int256(100e8));
            if (i < 12) {
                pools[i] = vm.parseAddress(POOL[i]);
                real[i] = toks[i];
            }
        }
        SlipstreamAdapter ad = new SlipstreamAdapter(ISlipstreamSwapRouter(ROUTER), USDC, real, pools);
        IndexVaultFactory f = new IndexVaultFactory(oracle, USDC, address(ad), 1 hours, t, caps);
        vm.prank(user);
        IndexVault v = IndexVault(f.createVault());
        vm.startPrank(user);
        v.setComponents(c);
        v.setRules(IIndexVault.Rules({driftThresholdBps: 100, minRebalanceInterval: 0, maxSlippageBps: 100}));
        (bool ok,) = USDC.call(abi.encodeWithSignature("approve(address,uint256)", address(v), type(uint256).max));
        assertTrue(ok);
        bytes[] memory legs = new bytes[](20);
        for (uint256 i; i < 20; ++i) legs[i] = abi.encodeCall(SlipstreamAdapter.buy, (toks[i % 12], 800e6, 0));
        uint256 g = gasleft();
        v.deposit(16_000e6, legs);
        g -= gasleft();
        vm.stopPrank();
        console.log("gas, deposit with 20 legs / 20 components:", g);
    }

    function test_basket_buy_through_real_router_hits_the_measured_pools() public {
        bytes[] memory legs = new bytes[](12);
        uint256[] memory poolBefore = new uint256[](12);
        for (uint256 i; i < 12; ++i) {
            legs[i] = _leg(toks[i], 800e6);
            poolBefore[i] = IERC20(USDC).balanceOf(vm.parseAddress(POOL[i]));
        }
        uint256 g = gasleft();
        vm.prank(user);
        vault.deposit(9_600e6, legs);
        g -= gasleft();
        console.log("gas, deposit with 12 legs / 12 components:", g);

        for (uint256 i; i < 12; ++i) {
            // the USDC went into the pool from the evidence (net of the pool fee going to LPs/gauge, still >= 99%)
            assertGe(IERC20(USDC).balanceOf(vm.parseAddress(POOL[i])) - poolBefore[i], 790e6, "leg did not hit the measured pool");
            assertGt(IERC20(toks[i]).balanceOf(address(vault)), 0);
        }
        (uint256 v,) = vault.totalValue();
        console.log("value after buying with 9600 USDC:", v);
        assertGe(v, 9_600e6 * 99 / 100);
    }

    function test_thin_pool_leg_over_its_cap_is_refused_on_the_real_router() public {
        bytes[] memory legs = new bytes[](1);
        legs[0] = _leg(toks[10], 6_000e6); // INTC cap is 5,000
        vm.prank(user);
        vm.expectPartialRevert(IIndexVault.ImpactCapExceeded.selector);
        vault.deposit(6_000e6, legs);
    }

    /// Same 12 swaps sent straight to the router from a plain account: the baseline against which the vault's
    /// per-leg balance reads and approvals are an overhead.
    function test_gas_baseline_same_swaps_without_the_vault() public {
        deal(USDC, address(this), 9_600e6);
        (bool ok,) = USDC.call(abi.encodeWithSignature("approve(address,uint256)", ROUTER, type(uint256).max));
        assertTrue(ok);
        uint256 g = gasleft();
        for (uint256 i; i < 12; ++i) {
            ISlipstreamRouter(ROUTER).exactInputSingle(
                ISlipstreamRouter.ExactInputSingleParams(USDC, toks[i], TS, address(this), block.timestamp, 800e6, 0, 0)
            );
        }
        g -= gasleft();
        console.log("gas, the same 12 swaps without the vault:", g);
    }
}
