// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISessionOracle} from "./ISessionOracle.sol";
import {IndexVault} from "./IndexVault.sol";

/// @title IndexVaultFactory
/// @notice Creates vaults as minimal proxies. Holds no funds and has no owner: every parameter below is fixed
/// at deployment. A change of oracle, router or any cap means deploying a new factory; existing vaults are unaffected.
/// The per-token caps reflect the liquidity measured when the factory was deployed (data/impact_sweep.csv).
contract IndexVaultFactory {
    ISessionOracle public immutable oracle;
    address public immutable usdc;
    address public immutable router;
    uint32 public immutable multiplierWindowSecs;
    address public immutable implementation;

    mapping(address => uint256) public capOf;
    address[] private _allowed;

    address[] private _vaults;
    mapping(address => address[]) private _vaultsOf;

    event VaultCreated(address indexed owner, address indexed vault, uint256 indexed id);

    error LengthMismatch();
    error ZeroCap(address token);
    error DuplicateToken(address token);
    error ZeroAddress();
    error ZeroWindow();

    constructor(
        ISessionOracle oracle_,
        address usdc_,
        address router_,
        uint32 multiplierWindowSecs_,
        address[] memory tokens,
        uint256[] memory caps
    ) {
        if (address(oracle_) == address(0) || usdc_ == address(0) || router_ == address(0)) revert ZeroAddress();
        if (tokens.length != caps.length) revert LengthMismatch();
        // the same window is the settle time after an observed multiplier change; zero would let the two entry points disagree
        if (multiplierWindowSecs_ == 0) revert ZeroWindow();
        oracle = oracle_;
        usdc = usdc_;
        router = router_;
        multiplierWindowSecs = multiplierWindowSecs_;
        for (uint256 i; i < tokens.length; ++i) {
            if (caps[i] == 0) revert ZeroCap(tokens[i]);
            if (capOf[tokens[i]] != 0) revert DuplicateToken(tokens[i]);
            capOf[tokens[i]] = caps[i];
            _allowed.push(tokens[i]);
        }
        implementation = address(new IndexVault());
    }

    function createVault() external returns (address vault) {
        address impl = implementation;
        assembly {
            let p := mload(0x40)
            mstore(p, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(p, 0x14), shl(0x60, impl))
            mstore(add(p, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            vault := create(0, p, 0x37)
        }
        require(vault != address(0), "clone failed");
        IndexVault(vault).initialize(msg.sender);
        uint256 id = _vaults.length;
        _vaults.push(vault);
        _vaultsOf[msg.sender].push(vault);
        emit VaultCreated(msg.sender, vault, id);
    }

    function vaultsOf(address owner) external view returns (address[] memory) {
        return _vaultsOf[owner];
    }

    function vaultCount() external view returns (uint256) {
        return _vaults.length;
    }

    function allVaults(uint256 offset, uint256 limit) external view returns (address[] memory page) {
        uint256 total = _vaults.length;
        if (offset >= total) return page;
        uint256 end = offset + limit > total ? total : offset + limit;
        page = new address[](end - offset);
        for (uint256 i = offset; i < end; ++i) page[i - offset] = _vaults[i];
    }

    function allowedTokens() external view returns (address[] memory) {
        return _allowed;
    }
}
