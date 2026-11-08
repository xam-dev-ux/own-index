// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ISlipstreamSwapRouter {
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

    function exactInputSingle(ExactInputSingleParams calldata params) external returns (uint256 amountOut);
    function factory() external view returns (address);
}

interface ISlipstreamFactory {
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address);
}

/// @title SlipstreamAdapter
/// @notice The only entry the vault's factory points at. It exposes two functions, `buy` and `sell`, and nothing else:
/// single-hop swaps between USDC and one listed token, on tick spacing 10, through the pool that was measured.
/// There is no multi-hop path, no other tick spacing and no other pair, so the vault's per-token cap always refers
/// to the pool the liquidity evidence was taken from. It holds no funds and has no owner or setters.
/// The vault never reads the calldata; it values balances before and after. This contract removes the routes the
/// vault would otherwise have to recognise.
contract SlipstreamAdapter {
    int24 public constant TICK_SPACING = 10;

    ISlipstreamSwapRouter public immutable router;
    address public immutable usdc;
    mapping(address => address) public poolOf; // token => the measured pool; zero = not allowed
    address[] private _tokens;

    error NotListed(address token);
    error PoolMismatch(address token, address expected, address actual);
    error LengthMismatch();
    error ZeroAmount();
    error TransferFailed();

    constructor(ISlipstreamSwapRouter router_, address usdc_, address[] memory tokens, address[] memory pools) {
        if (tokens.length != pools.length) revert LengthMismatch();
        router = router_;
        usdc = usdc_;
        address factory = router_.factory();
        for (uint256 i; i < tokens.length; ++i) {
            address actual = ISlipstreamFactory(factory).getPool(usdc_, tokens[i], TICK_SPACING);
            if (actual == address(0) || actual != pools[i]) revert PoolMismatch(tokens[i], pools[i], actual);
            poolOf[tokens[i]] = actual;
            _tokens.push(tokens[i]);
        }
    }

    /// @notice Spends `usdcIn` of the caller's USDC (approval required) and sends the token to the caller.
    function buy(address token, uint256 usdcIn, uint256 minOut) external returns (uint256 out) {
        out = _swap(usdc, token, usdcIn, minOut, token);
    }

    /// @notice Spends `tokenIn` of the caller's token (approval required) and sends USDC to the caller.
    function sell(address token, uint256 tokenIn, uint256 minOut) external returns (uint256 out) {
        out = _swap(token, usdc, tokenIn, minOut, token);
    }

    function listedTokens() external view returns (address[] memory) {
        return _tokens;
    }

    function _swap(address tokenIn, address tokenOut, uint256 amountIn, uint256 minOut, address listed)
        internal
        returns (uint256 out)
    {
        if (poolOf[listed] == address(0)) revert NotListed(listed);
        if (amountIn == 0) revert ZeroAmount();
        _call(tokenIn, abi.encodeWithSignature("transferFrom(address,address,uint256)", msg.sender, address(this), amountIn));
        _call(tokenIn, abi.encodeWithSignature("approve(address,uint256)", address(router), amountIn));
        out = router.exactInputSingle(
            ISlipstreamSwapRouter.ExactInputSingleParams(
                tokenIn, tokenOut, TICK_SPACING, msg.sender, block.timestamp, amountIn, minOut, 0
            )
        );
        _call(tokenIn, abi.encodeWithSignature("approve(address,uint256)", address(router), 0));
    }

    function _call(address token, bytes memory data) internal {
        (bool ok, bytes memory ret) = token.call(data);
        if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
    }
}
