// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SlipstreamAdapter, ISlipstreamSwapRouter} from "../src/SlipstreamAdapter.sol";
import {MockToken, MockSlipstream} from "../src/testing/MockTrade.sol";

contract SlipstreamAdapterTest is Test {
    MockSlipstream ss;
    MockToken usdc;
    MockToken stock;
    MockToken other;
    SlipstreamAdapter ad;
    address pool = address(0xB001);
    address caller = address(0xCA11);

    function setUp() public {
        ss = new MockSlipstream();
        usdc = new MockToken("USDC", 6);
        stock = new MockToken("S", 8);
        other = new MockToken("O", 8);
        ss.setPool(address(usdc), address(stock), 10, pool);
        ss.setPool(address(usdc), address(other), 100, address(0xB002)); // exists, but on another tick spacing
        address[] memory t = new address[](1);
        t[0] = address(stock);
        address[] memory p = new address[](1);
        p[0] = pool;
        ad = new SlipstreamAdapter(ISlipstreamSwapRouter(address(ss)), address(usdc), t, p);
        usdc.mint(address(ss), 1e15);
        stock.mint(address(ss), 1e15);
        usdc.mint(caller, 1000e6);
        stock.mint(caller, 100e8);
        vm.startPrank(caller);
        usdc.approve(address(ad), type(uint256).max);
        stock.approve(address(ad), type(uint256).max);
        vm.stopPrank();
    }

    function test_buy_and_sell_pay_the_caller_and_use_tick_spacing_10() public {
        vm.prank(caller);
        ad.buy(address(stock), 100e6, 0);
        assertEq(ss.lastTickSpacing(), 10);
        assertEq(stock.balanceOf(caller), 100e8 + 100e6);
        vm.prank(caller);
        ad.sell(address(stock), 5e8, 0);
        assertEq(usdc.balanceOf(caller), 900e6 + 5e8);
        // holds nothing
        assertEq(usdc.balanceOf(address(ad)), 0);
        assertEq(stock.balanceOf(address(ad)), 0);
        assertEq(usdc.allowance(address(ad), address(ss)), 0);
        assertEq(stock.allowance(address(ad), address(ss)), 0);
    }

    function test_unlisted_token_is_refused_even_if_a_pool_exists_elsewhere() public {
        other.mint(caller, 1e8);
        vm.startPrank(caller);
        vm.expectRevert(abi.encodeWithSelector(SlipstreamAdapter.NotListed.selector, address(other)));
        ad.buy(address(other), 1e6, 0);
        vm.expectRevert(abi.encodeWithSelector(SlipstreamAdapter.NotListed.selector, address(other)));
        ad.sell(address(other), 1e8, 0);
        vm.stopPrank();
    }

    function test_zero_amount_refused() public {
        vm.prank(caller);
        vm.expectRevert(SlipstreamAdapter.ZeroAmount.selector);
        ad.buy(address(stock), 0, 0);
    }

    function test_constructor_refuses_a_pool_that_is_not_the_one_given() public {
        address[] memory t = new address[](1);
        t[0] = address(stock);
        address[] memory p = new address[](1);
        p[0] = address(0xDEAD);
        vm.expectRevert(abi.encodeWithSelector(SlipstreamAdapter.PoolMismatch.selector, address(stock), address(0xDEAD), pool));
        new SlipstreamAdapter(ISlipstreamSwapRouter(address(ss)), address(usdc), t, p);
        // a token with no pool on tick spacing 10 cannot be listed
        t[0] = address(other);
        p[0] = address(0xB002);
        vm.expectRevert(abi.encodeWithSelector(SlipstreamAdapter.PoolMismatch.selector, address(other), address(0xB002), address(0)));
        new SlipstreamAdapter(ISlipstreamSwapRouter(address(ss)), address(usdc), t, p);
    }

    function test_no_other_function_is_exposed() public {
        // an exactInput-style or arbitrary call does not exist: the fallback reverts
        vm.prank(caller);
        (bool ok,) = address(ad).call(abi.encodeWithSignature("exactInputSingle((address,address,int24,address,uint256,uint256,uint256,uint160))", address(usdc)));
        assertFalse(ok);
        (ok,) = address(ad).call(abi.encodeWithSignature("exactInput((bytes,address,uint256,uint256,uint256))"));
        assertFalse(ok);
    }
}
