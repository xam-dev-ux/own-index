// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {Test, console} from "forge-std/Test.sol";
interface IPool {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, bool);
    function liquidity() external view returns (uint128);
    function fee() external view returns (uint24);
    function token0() external view returns (address);
    function swap(address, bool, int256, uint160, bytes calldata) external returns (int256, int256);
}
interface IERC20 { function transfer(address,uint256) external returns (bool);}
contract Sweep is Test {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address pool; bool z;
    function uniswapV3SwapCallback(int256 a0, int256 a1, bytes calldata) external {
        require(msg.sender == pool);
        uint256 owed = a0 > 0 ? uint256(a0) : uint256(a1);
        IERC20(USDC).transfer(pool, owed);
    }
    function _one(string memory n, address p) internal {
        pool = p; z = IPool(p).token0() == USDC;
        uint256[11] memory a = [uint256(500e6),1000e6,2000e6,3000e6,5000e6,7500e6,10000e6,15000e6,20000e6,30000e6,50000e6];
        string memory line = n;
        for (uint256 i; i < 11; i++) {
            uint256 snap = vm.snapshotState();
            (uint160 sq,,,,,) = IPool(p).slot0();
            uint256 fee = IPool(p).fee();
            deal(USDC, address(this), a[i]);
            uint256 Q = 2**96;
            int256 imp;
            try IPool(p).swap(address(this), z, int256(a[i]), z ? 4295128740 : 1461446703485210103287273052203988822378723970341, "") returns (int256 r0, int256 r1) {
                uint256 out = z ? uint256(-r1) : uint256(-r0);
                uint256 dx = a[i] * (1e6 - fee) / 1e6;
                uint256 idealRatio = z ? (uint256(sq) * uint256(sq) / Q) : 0; // spot*Q
                if (z) imp = int256(1e5) - int256((out * Q * 1e5) / (dx * idealRatio));
                else imp = int256(1e5) - int256((out * uint256(sq) / Q * uint256(sq) / Q) * 1e5 / dx);
            } catch { imp = -999999; }
            line = string.concat(line, ",", vm.toString(imp));
            vm.revertToState(snap);
        }
        console.log(line);
    }
    function test_all() public {
        _one("AAPL",0xF5FCB9CDAFcE67d50AfEf298F88E709d2B946BA6);
        _one("AMZN",0x532e0F46d1e528507FC9454d5847C231f23bDDf6);
        _one("GOOGL",0x16c70F04C3080a127486Cdf5a4C33c066bBF47C3);
        _one("META",0xd072410fa13D242e1d53721Bcf7AF02e3455DC96);
        _one("MSFT",0x2740C0faAb738F6e346e545fDE02aEF9B1A01ee7);
        _one("MSTR",0x66DCd42E6314B287110922AE36cB2a8bdEECc153);
        _one("NVDA",0xF668e21993f0ACd7ab00BB1cFbAeD0df28A3C8EC);
        _one("SNDK",0x2836e062a3fe75943a7F4A552E2365b98E414E75);
        _one("SPCX",0x880dB7Dda4407D99508574E680d067D1164B3cFE);
        _one("TSLA",0x7A33000372f3F028f074182CCb9d16cBEEfBF920);
        _one("INTC",0x3D384288fA79B51De882B06B617aB7989CcAd4f3);
        _one("CRCL",0x294666AD6a415E8C33Af801225c04079BB4f1133);
    }
}
