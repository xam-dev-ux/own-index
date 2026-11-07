// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";

interface IPool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, bool);
    function liquidity() external view returns (uint128);
    function fee() external view returns (uint24);
    function swap(address, bool, int256, uint160, bytes calldata) external returns (int256, int256);
}
interface IERC20 { function approve(address,uint256) external returns (bool); function balanceOf(address) external view returns (uint256); function transfer(address,uint256) external returns (bool);}

contract ImpactCheck is Test {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address pool;
    function uniswapV3SwapCallback(int256 a0, int256, bytes calldata) external {
        require(msg.sender == pool, "cb");
        if (a0 > 0) IERC20(USDC).transfer(pool, uint256(a0));
    }
    function _check(string memory name, address p) internal {
        pool = p;
        uint256[3] memory amts = [uint256(100e6), 1000e6, 10000e6];
        for (uint256 i; i < 3; i++) {
            uint256 snap = vm.snapshotState();
            (uint160 sq,,,,,) = IPool(p).slot0();
            uint256 L = IPool(p).liquidity();
            uint256 fee = IPool(p).fee();
            deal(USDC, address(this), amts[i]);
            (int256 a0, int256 a1) = IPool(p).swap(address(this), true, int256(amts[i]), 4295128740, "");
            uint256 out = uint256(-a1);
            // predicted (single range, fee off the input)
            uint256 dx = amts[i] * (1e6 - fee) / 1e6;
            uint256 Q = 2**96;
            uint256 sqn = (L * uint256(sq)) / (L + (dx * uint256(sq)) / Q);
            uint256 predOut = L * (uint256(sq) - sqn) / Q;
            // impact vs spot, bps*10 (ex fee): 1 - (out/dx)/spot ; spot = (sq/Q)^2 raw units
            uint256 spotNum = uint256(sq) * uint256(sq) / Q; // spot*Q
            int256 realImp = int256(1e5) - int256((out * Q * 1e5) / (dx * spotNum));
            int256 predImp = int256(1e5) - int256((predOut * Q * 1e5) / (dx * spotNum));
            console.log(name, amts[i] / 1e6);
            console.log("  used", uint256(a0), "fee_ppm", fee);
            console.log("  real  impact (1e-5):"); console.logInt(realImp);
            console.log("  pred  impact (1e-5):"); console.logInt(predImp);
            console.log("  out real/pred:", out, predOut);
            vm.revertToState(snap);
        }
    }
    function test_INTC() public { _check("INTC", 0x3D384288fA79B51De882B06B617aB7989CcAd4f3); }
    function test_AMZN() public { _check("AMZN", 0x532e0F46d1e528507FC9454d5847C231f23bDDf6); }
    function test_CRCL() public { _check("CRCL", 0x294666AD6a415E8C33Af801225c04079BB4f1133); }
}
