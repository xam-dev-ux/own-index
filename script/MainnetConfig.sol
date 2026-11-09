// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

/// @notice Everything about the mainnet deployment that is a fact (addresses, evidence-derived caps) lives here, once,
/// and is shared by DeployMainnet and VerifyMainnet so the two cannot disagree. Everything that is still a
/// MEASUREMENT or a CALENDAR DECISION is not here: it is read from the environment and is refused while it
/// says PENDING or DISPOSABLE (see `_u`).
abstract contract MainnetConfig is Script {
    address internal constant DEPLOYER = 0x8F058fE6b568D97f85d517Ac441b52B95722fDDe;
    address internal constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    /// Aero Slipstream router for factory 0x9CB22058...7a76 (dromos-labs/metadex-slipstream-public, cl-base.json).
    address internal constant SLIPSTREAM_ROUTER = 0x9Ee35Bf1bd69a03c6F0393582030fCe8Bb93D418;
    /// Coinbase onchain registry, read only for the paused flag. Answered getOracleParams(AAPLc) at the pinned block.
    address internal constant REGISTRY = 0x3f3E8cf41cdd3b1D118c16471aB0113DfDDd5CaD;

    // Unix times used only by the calendar guards (UTC).
    uint256 internal constant THANKSGIVING_NOON_ET = 1795712400; // 2026-11-26 17:00 UTC
    uint256 internal constant DAY_AFTER_AFTERNOON_ET = 1795809600; // 2026-11-27 20:00 UTC
    uint256 internal constant CALENDAR_MUST_REACH = 1795824000; // 2026-11-28 00:00 UTC

    struct Stock {
        string symbol;
        address token;
        address feed;
        address secondaryFeed; // 24/7 feed, address(0) if none
        string secondaryDescription;
        address pool;          // the pool in data/impact.json (Aero CL factory, tick spacing 10)
        uint256 cap;           // USDC units, docs/vault-design.md
    }

    /// Number of tokens in the index. INTC and CRCL were dropped (docs/liquidity-in-session.md): their pools were unusable
    /// at two of three in-session blocks, and the rule is the minimum over session blocks.
    uint256 internal constant N = 10;

    function _universe() internal pure returns (Stock[10] memory s) {
        // caps: the largest swept size with at most 50 bps of impact, taken as the MINIMUM over the three in-session blocks
        // in data/impact_sweep_session.csv (never the Saturday block). A cap of 50,000 is the sweep ceiling, which is
        // where measurement stopped, not a measured limit.
        s[0] = Stock("AAPL", 0xb200000000000000000000C2e324d24d7eEcd1fb, 0x787f13dEa48Db0897CbCDD985de77809D837F988, address(0), "", 0xF5FCB9CDAFcE67d50AfEf298F88E709d2B946BA6, 50_000e6);
        s[1] = Stock("AMZN", 0xb200000000000000000000d9192b6B456483C2E8, 0x06A8E4b3aBB3B7543d8396FB2B763d22820cB295, address(0), "", 0x532e0F46d1e528507FC9454d5847C231f23bDDf6, 50_000e6);
        s[2] = Stock("GOOGL", 0xb2000000000000000000002D0BA3164cc74f58B7, 0x5bF49E0ffA937CE2FfF033c739aD7C634c4D34F2, 0xdD9b9EC942477AA672a15adF91AC5089BD86cD85, "Coinbase GOOGL (24/7)", 0x16c70F04C3080a127486Cdf5a4C33c066bBF47C3, 50_000e6);
        s[3] = Stock("META", 0xb2000000000000000000008bC8786B856E61707C, 0x6526aE6797A76123638b863AeE4dD27Ba4E4b27D, address(0), "", 0xd072410fa13D242e1d53721Bcf7AF02e3455DC96, 50_000e6);
        s[4] = Stock("MSFT", 0xB200000000000000000000Ab99cFa739E253872B, 0xeB10A6c9aa7E537aEd766C08c35Dae35B321b18c, address(0), "", 0x2740C0faAb738F6e346e545fDE02aEF9B1A01ee7, 20_000e6);
        s[5] = Stock("MSTR", 0xb2000000000000000000004884b426556b92883d, 0xB3cE282CD188b35DA0E38D8Bc7d58e33173D202a, address(0), "", 0x66DCd42E6314B287110922AE36cB2a8bdEECc153, 50_000e6);
        s[6] = Stock("NVDA", 0xb20000000000000000000078ee7ce2fE4908108C, 0x04689a41629776563E6822F76f2e57D148d28513, 0x48D9731AF6cc55b879FE76a4Bd1A6c2C0bDaf944, "Coinbase NVDA (24/7)", 0xF668e21993f0ACd7ab00BB1cFbAeD0df28A3C8EC, 30_000e6);
        s[7] = Stock("SNDK", 0xb200000000000000000000397293Cb8cda9a10c5, 0x388b0dC46C0Fb05A74BeE0994fa5b02c6Fcca2eA, address(0), "", 0x2836e062a3fe75943a7F4A552E2365b98E414E75, 30_000e6);
        s[8] = Stock("SPCX", 0xb2000000000000000000007b9fcbd005511aCBd5, 0x6A634B235903C4ad6376892180d6fF8612e3Fa68, address(0), "", 0x880dB7Dda4407D99508574E680d067D1164B3cFE, 30_000e6);
        s[9] = Stock("TSLA", 0xb2000000000000000000001e800a7f5189430cD0, 0xFaf869185383a24F8cb00e27BdA6b63B9905DCb4, 0xa5Ccd0315346b9A8A1D0AFEcD7Cc4e820e405e96, "Coinbase TSLA (24/7)", 0x7A33000372f3F028f074182CCb9d16cBEEfBF920, 7_500e6);
    }

    struct OracleParams {
        uint32 openOffset;
        uint32 closeOffset;
        uint32 heartbeat;
        uint32 heartbeatMargin;
        uint32 comparisonWindow;
        uint64 confirmedUntil;
        uint32 multiplierWindow;
        uint32[10] thresholds;
        uint64[] closureStart;
        uint64[] closureEnd;
        uint8[] closureKind; // 0 HOLIDAY, 1 EARLY_CLOSE
    }

    /// @dev Reads a parameter from the environment. A value still marked PENDING or DISPOSABLE, or an empty or missing
    /// one, makes the script fail here, loudly, instead of deploying with a placeholder.
    function _s(string memory name) internal view returns (string memory v) {
        v = vm.envOr(name, string(""));
        require(bytes(v).length != 0, string.concat("PARAM MISSING: ", name));
        require(!_has(v, "PENDING") && !_has(v, "DISPOSABLE"), string.concat("PARAM STILL A PLACEHOLDER: ", name));
    }

    function _u(string memory name) internal view returns (uint256) {
        return vm.parseUint(_s(name));
    }

    function _has(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length > h.length) return false;
        for (uint256 i; i + n.length <= h.length; ++i) {
            bool ok = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function _params(Stock[10] memory u) internal view returns (OracleParams memory p) {
        p.openOffset = uint32(_u("ORACLE_OPEN_OFFSET"));
        p.closeOffset = uint32(_u("ORACLE_CLOSE_OFFSET"));
        p.heartbeat = uint32(_u("ORACLE_HEARTBEAT"));
        p.heartbeatMargin = uint32(_u("ORACLE_HEARTBEAT_MARGIN"));
        p.comparisonWindow = uint32(_u("ORACLE_COMPARISON_WINDOW"));
        p.confirmedUntil = uint64(_u("CALENDAR_CONFIRMED_UNTIL"));
        p.multiplierWindow = uint32(_u("MULTIPLIER_WINDOW_SECS"));
        for (uint256 i; i < N; ++i) p.thresholds[i] = uint32(_u(string.concat("THRESHOLD_", u[i].symbol)));
        uint256 n = _u("CLOSURE_COUNT");
        p.closureStart = new uint64[](n);
        p.closureEnd = new uint64[](n);
        p.closureKind = new uint8[](n);
        for (uint256 i; i < n; ++i) {
            string memory k = string.concat("CLOSURE_", vm.toString(i));
            p.closureStart[i] = uint64(_u(string.concat(k, "_START")));
            p.closureEnd[i] = uint64(_u(string.concat(k, "_END")));
            p.closureKind[i] = uint8(_u(string.concat(k, "_KIND")));
        }
        _sanity(p);
    }

    /// @dev Shape checks that catch a wrong value, not just a missing one.
    function _sanity(OracleParams memory p) internal view {
        require(block.chainid == 8453, "mainnet only");
        require(p.openOffset < p.closeOffset && p.closeOffset <= 7 days, "window offsets");
        require(p.heartbeat == 86400, "heartbeat is the feeds' 24h");
        require(p.comparisonWindow > 0 && p.multiplierWindow > 0, "windows must be positive");
        for (uint256 i; i < N; ++i) {
            require(p.thresholds[i] > 0 && p.thresholds[i] < p.heartbeat, "threshold out of range");
        }
        require(p.confirmedUntil >= CALENDAR_MUST_REACH, "calendar must be confirmed past 2026-11-27");
        // Thanksgiving must be loaded: a HOLIDAY covering Thu 26 Nov noon ET and an EARLY_CLOSE covering Fri 27 Nov afternoon ET.
        bool holiday;
        bool half;
        for (uint256 i; i < p.closureStart.length; ++i) {
            require(p.closureKind[i] <= 1, "closure kind");
            if (i > 0) require(p.closureStart[i] >= p.closureEnd[i - 1], "closures out of order");
            if (p.closureKind[i] == 0 && p.closureStart[i] <= THANKSGIVING_NOON_ET && p.closureEnd[i] > THANKSGIVING_NOON_ET) holiday = true;
            if (p.closureKind[i] == 1 && p.closureStart[i] <= DAY_AFTER_AFTERNOON_ET && p.closureEnd[i] > DAY_AFTER_AFTERNOON_ET) half = true;
        }
        require(holiday, "Thanksgiving (26 Nov) closure not loaded");
        require(half, "27 Nov early close not loaded");
    }
}
