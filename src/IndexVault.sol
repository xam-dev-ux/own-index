// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISessionOracle} from "./ISessionOracle.sol";
import {IIndexVault} from "./IIndexVault.sol";
import {BaseTimeLib} from "./BaseTimeLib.sol";

/// @dev What a vault reads from the factory that created it. All immutable per factory deployment.
interface IVaultEnvironment {
    function oracle() external view returns (ISessionOracle);
    function usdc() external view returns (address);
    function router() external view returns (address);
    function multiplierWindowSecs() external view returns (uint32);
    /// @notice Largest value (USDC units) a single component may move in one operation. 0 = token not allowed.
    function capOf(address token) external view returns (uint256);
}

interface IERC20Min {
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
}

/// @title IndexVault
/// @notice Self-custodial, user-weighted index vault. One owner, no share token, no fees.
/// It trades only against FRESH marks of the session oracle, treats a basket as atomic, and never gates withdrawal.
/// WeekendMark is NOT a liquidation oracle and this vault never uses it as one.
/// @dev Deployed as an EIP-1167 clone by IndexVaultFactory. The vault has no knowledge of Builder Codes.
contract IndexVault is IIndexVault {
    uint256 private constant MAX_COMPONENTS = 20;
    uint16 private constant MAX_SLIPPAGE_CAP_BPS = 500;

    IVaultEnvironment public factory;
    address public owner;
    Component[] private _components;
    Rules public rules;

    uint64 public lastRebalanceAt; // seconds
    uint256 private _refusals;
    uint256 private _rebalances;
    bool private _locked;

    constructor() {
        factory = IVaultEnvironment(address(1)); // the implementation itself can never be initialised
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert Reentrancy();
        _locked = true;
        _;
        _locked = false;
    }

    function initialize(address owner_) external {
        if (address(factory) != address(0)) revert AlreadyInitialized();
        factory = IVaultEnvironment(msg.sender);
        owner = owner_;
        emit OwnerSet(owner_);
    }

    // ================================================================ evaluation (single source of truth)

    /// @dev Result of the pre-trade checks. Both `rebalance` and `tryRebalance` (and `rebalanceStatus`)
    /// consume exactly this, so simulation and execution cannot disagree about a pre-trade refusal.
    struct Evaluation {
        Refusal[] refusals;
        uint256 n;
        uint256[] prices;  // 8-decimal oracle prices, 0 where the mark is not usable
        uint256[] values;  // component values in USDC units
        uint256 componentValue;
        uint16 maxDriftBps;
    }

    function _evaluate(Action action) internal view returns (Evaluation memory e) {
        uint256 len = _components.length;
        if (len == 0) revert BadComponents();
        IVaultEnvironment env = factory;
        ISessionOracle oracle = env.oracle();
        uint256 window = env.multiplierWindowSecs();
        e.refusals = new Refusal[](len + 2);
        e.prices = new uint256[](len);
        e.values = new uint256[](len);
        bool marksOk = true;

        for (uint256 i; i < len; ++i) {
            address token = _components[i].token;
            (RefusalKind k, ISessionOracle.Cause cause, uint256 price) = _classify(oracle, token);
            if (k == RefusalKind.NONE && _multiplierImminent(token, window)) {
                k = RefusalKind.MULTIPLIER_CHANGE_IMMINENT;
            }
            if (k != RefusalKind.NONE) {
                marksOk = false;
                e.refusals[e.n++] = Refusal(k, token, cause);
            } else {
                e.prices[i] = price;
                e.values[i] = _valueOf(token, IERC20Min(token).balanceOf(address(this)), price);
                e.componentValue += e.values[i];
            }
        }

        if (action == Action.REBALANCE) {
            uint256 next = uint256(lastRebalanceAt) + rules.minRebalanceInterval;
            if (lastRebalanceAt != 0 && block.timestamp < next) {
                e.refusals[e.n++] = Refusal(RefusalKind.TOO_SOON, address(0), ISessionOracle.Cause.NONE);
            }
            if (marksOk) {
                e.maxDriftBps = _maxDrift(e.values, e.componentValue);
                if (e.maxDriftBps < rules.driftThresholdBps || e.componentValue == 0) {
                    e.refusals[e.n++] = Refusal(RefusalKind.NO_DRIFT, address(0), ISessionOracle.Cause.NONE);
                }
            }
        }
    }

    function _classify(ISessionOracle oracle, address token)
        internal
        view
        returns (RefusalKind k, ISessionOracle.Cause cause, uint256 price)
    {
        try oracle.markOf(token) returns (ISessionOracle.Mark memory m) {
            cause = m.cause;
            ISessionOracle.Session s = m.session;
            if (s == ISessionOracle.Session.FRESH) {
                if (m.price <= 0) return (RefusalKind.FEED_FAULT, ISessionOracle.Cause.FEED_INVALID, 0);
                return (RefusalKind.NONE, ISessionOracle.Cause.NONE, uint256(m.price));
            }
            if (s == ISessionOracle.Session.CLOSED) return (RefusalKind.MARKET_CLOSED, cause, 0);
            if (s == ISessionOracle.Session.PAUSED) return (RefusalKind.CORPORATE_ACTION_PAUSE, cause, 0);
            if (s == ISessionOracle.Session.STALE_IN_SESSION && cause == ISessionOracle.Cause.AWAITING_FIRST_PRINT) {
                return (RefusalKind.AWAITING_FIRST_PRINT, cause, 0);
            }
            return (RefusalKind.FEED_FAULT, cause, 0); // other STALE_IN_SESSION, UNKNOWN
        } catch {
            return (RefusalKind.FEED_FAULT, ISessionOracle.Cause.FEED_INVALID, 0);
        }
    }

    /// @dev The unit of `effectiveAt()` has not been seen with a live pending change (none exists on chain).
    /// It is read as a unix timestamp in seconds. Any nonzero value that does not look like one (a block number,
    /// a millisecond timestamp, anything else) is treated as an imminent change, so a wrong unit can only make the
    /// vault refuse more, never trade through a multiplier change it failed to see.
    uint256 private constant MIN_PLAUSIBLE_SECONDS = 1_600_000_000;
    uint256 private constant MAX_PLAUSIBLE_SECONDS = 100_000_000_000;

    function _multiplierImminent(address token, uint256 window) internal view returns (bool) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("effectiveAt()"));
        if (!ok || ret.length < 32) return false;
        uint256 at = abi.decode(ret, (uint256));
        if (at == 0) return false;
        if (at < MIN_PLAUSIBLE_SECONDS || at > MAX_PLAUSIBLE_SECONDS) return true;
        return at >= block.timestamp && at - block.timestamp <= window;
    }

    function _effectiveAt(address token) internal view returns (uint256 at) {
        (bool ok, bytes memory ret) = token.staticcall(abi.encodeWithSignature("effectiveAt()"));
        if (ok && ret.length >= 32) at = abi.decode(ret, (uint256));
    }

    /// @dev `price` is a Chainlink Total Return Value and already includes the corporate-action multiplier.
    /// The raw balance is multiplied by it directly. The multiplier is never applied a second time.
    function _valueOf(address token, uint256 rawBalance, uint256 price) internal view returns (uint256) {
        uint8 tokDec = IERC20Min(token).decimals();
        uint8 usdcDec = IERC20Min(factory.usdc()).decimals();
        return rawBalance * price * (10 ** usdcDec) / ((10 ** tokDec) * 1e8);
    }

    function _maxDrift(uint256[] memory values, uint256 total) internal view returns (uint16 maxDrift) {
        if (total == 0) return 0;
        for (uint256 i; i < values.length; ++i) {
            uint256 w = values[i] * 10_000 / total;
            uint256 t = _components[i].targetWeightBps;
            uint256 d = w > t ? w - t : t - w;
            if (d > maxDrift) maxDrift = uint16(d);
        }
    }

    function _revertWith(Refusal memory r) internal view {
        if (r.kind == RefusalKind.MARKET_CLOSED) revert MarketClosed(r.token, r.cause);
        if (r.kind == RefusalKind.AWAITING_FIRST_PRINT) revert AwaitingFirstPrint(r.token);
        if (r.kind == RefusalKind.FEED_FAULT) revert FeedFault(r.token, r.cause);
        if (r.kind == RefusalKind.CORPORATE_ACTION_PAUSE) revert CorporateActionPause(r.token);
        if (r.kind == RefusalKind.MULTIPLIER_CHANGE_IMMINENT) {
            revert MultiplierChangeImminent(r.token, _effectiveAt(r.token));
        }
        if (r.kind == RefusalKind.NO_DRIFT) revert NoDriftDetected();
        if (r.kind == RefusalKind.TOO_SOON) revert RebalanceTooSoon(lastRebalanceAt + rules.minRebalanceInterval);
    }

    // ================================================================ trading

    /// @inheritdoc IIndexVault
    function rebalance(bytes[] calldata swapCalldata) external onlyOwner nonReentrant {
        Evaluation memory e = _evaluate(Action.REBALANCE);
        if (e.n > 0) _revertWith(e.refusals[0]);
        this.executeTrade(swapCalldata); // post-trade checks revert with their own errors
        _recordRebalance();
    }

    /// @inheritdoc IIndexVault
    function tryRebalance(bytes[] calldata swapCalldata) external onlyOwner nonReentrant returns (bool executed) {
        Evaluation memory e = _evaluate(Action.REBALANCE);
        if (e.n > 0) {
            _recordRefusals(e.refusals, e.n);
            return false;
        }
        try this.executeTrade(swapCalldata) {
            _recordRebalance();
            return true;
        } catch (bytes memory err) {
            bytes4 sel = err.length >= 4 ? bytes4(err) : bytes4(0);
            Refusal[] memory one = new Refusal[](1);
            if (sel == ImpactCapExceeded.selector) {
                address token;
                assembly {
                    token := mload(add(err, 36))
                }
                one[0] = Refusal(RefusalKind.IMPACT_CAP_EXCEEDED, token, ISessionOracle.Cause.NONE);
            } else if (sel == SlippageExceeded.selector) {
                one[0] = Refusal(RefusalKind.SLIPPAGE_EXCEEDED, address(0), ISessionOracle.Cause.NONE);
            } else {
                assembly {
                    revert(add(err, 32), mload(err)) // malformed calldata, router failure: the caller's error, not a market refusal
                }
            }
            _recordRefusals(one, 1);
            return false;
        }
    }

    /// @inheritdoc IIndexVault
    function deposit(uint256 usdcAmount, bytes[] calldata swapCalldata) external onlyOwner nonReentrant {
        Evaluation memory e = _evaluate(Action.DEPOSIT_WITH_SWAPS);
        if (e.n > 0) _revertWith(e.refusals[0]);
        _pull(factory.usdc(), msg.sender, usdcAmount);
        emit Deposited(factory.usdc(), usdcAmount);
        this.executeTrade(swapCalldata);
    }

    /// @dev Runs the router calls and then enforces, on balance deltas valued at oracle prices:
    ///  (1) every component moved by at most its immutable cap, summed over the legs of the batch (gross, not net), and
    ///  (2) the value lost across the batch is at most `maxSlippageBps` of the value bought.
    /// External only so that a failure can be caught (tryRebalance) and its swaps rolled back as a unit.
    function executeTrade(bytes[] calldata swaps) external {
        if (msg.sender != address(this)) revert NotSelf();
        IVaultEnvironment env = factory;
        address router = env.router();
        address usdc = env.usdc();
        uint256 len = _components.length;

        uint256[] memory prices = new uint256[](len);
        uint256[] memory beforeBal = new uint256[](len + 1);
        ISessionOracle oracle = env.oracle();
        for (uint256 i; i < len; ++i) {
            address t = _components[i].token;
            prices[i] = uint256(oracle.markOf(t).price);
            beforeBal[i] = IERC20Min(t).balanceOf(address(this));
            _approve(t, router, type(uint256).max);
        }
        beforeBal[len] = IERC20Min(usdc).balanceOf(address(this));
        _approve(usdc, router, type(uint256).max);

        uint256[] memory gross = new uint256[](len);
        for (uint256 i; i < swaps.length; ++i) {
            uint256[] memory pre = _componentBalances(len);
            (bool ok,) = router.call(swaps[i]);
            if (!ok) revert SwapFailed(i);
            _accumulateGross(gross, pre, prices);
        }

        for (uint256 i; i < len; ++i) _approve(_components[i].token, router, 0);
        _approve(usdc, router, 0);

        _checkOutcome(prices, beforeBal, gross);
    }

    function _componentBalances(uint256 len) internal view returns (uint256[] memory b) {
        b = new uint256[](len);
        for (uint256 i; i < len; ++i) b[i] = IERC20Min(_components[i].token).balanceOf(address(this));
    }

    /// @dev Adds, per component, the absolute value moved by ONE router call. Summing legs (not netting them) is what
    /// stops a buy and a sell of the same component in one batch from cancelling in the cap. No calldata is read.
    function _accumulateGross(uint256[] memory gross, uint256[] memory pre, uint256[] memory prices) internal view {
        for (uint256 i; i < gross.length; ++i) {
            address t = _components[i].token;
            uint256 post = IERC20Min(t).balanceOf(address(this));
            uint256 d = post >= pre[i] ? post - pre[i] : pre[i] - post;
            if (d != 0) gross[i] += _valueOf(t, d, prices[i]);
        }
    }

    function _checkOutcome(uint256[] memory prices, uint256[] memory beforeBal, uint256[] memory gross) internal view {
        uint256 len = prices.length;
        uint256 bought;
        uint256 sold;
        for (uint256 i; i < len; ++i) {
            address t = _components[i].token;
            uint256 cap = factory.capOf(t);
            if (gross[i] > cap) revert ImpactCapExceeded(t, gross[i], cap);
            uint256 afterBal = IERC20Min(t).balanceOf(address(this));
            if (afterBal >= beforeBal[i]) bought += _valueOf(t, afterBal - beforeBal[i], prices[i]);
            else sold += _valueOf(t, beforeBal[i] - afterBal, prices[i]);
        }
        uint256 usdcAfter = IERC20Min(factory.usdc()).balanceOf(address(this));
        if (usdcAfter >= beforeBal[len]) bought += usdcAfter - beforeBal[len];
        else sold += beforeBal[len] - usdcAfter;

        if (sold > bought) {
            uint256 loss = sold - bought;
            uint256 allowed = bought * rules.maxSlippageBps / 10_000;
            if (loss > allowed) revert SlippageExceeded(bought, loss, allowed);
        }
    }

    function _recordRebalance() internal {
        uint256 id = ++_rebalances;
        lastRebalanceAt = uint64(block.timestamp);
        emit Rebalanced(id, msg.sender, uint64(BaseTimeLib.timestampMs()));
    }

    function _recordRefusals(Refusal[] memory rs, uint256 n) internal {
        uint256 id = ++_refusals;
        uint64 ms = uint64(BaseTimeLib.timestampMs());
        for (uint256 i; i < n; ++i) emit RebalanceRefused(id, rs[i].kind, rs[i].token, rs[i].cause, ms);
    }

    // ================================================================ custody (never consults oracle or router)

    /// @inheritdoc IIndexVault
    function depositInKind(address[] calldata tokens, uint256[] calldata amounts) external onlyOwner nonReentrant {
        if (tokens.length != amounts.length) revert LengthMismatch();
        for (uint256 i; i < tokens.length; ++i) {
            _pull(tokens[i], msg.sender, amounts[i]);
            emit Deposited(tokens[i], amounts[i]);
        }
    }

    /// @inheritdoc IIndexVault
    function withdraw(address asset, uint256 amount, address to) external onlyOwner nonReentrant {
        _push(asset, to, amount);
        emit Withdrawn(asset, amount, to);
    }

    /// @inheritdoc IIndexVault
    /// @dev A token whose transfer fails (for example a blacklisted recipient) is skipped and does not block the
    /// others; `withdraw(asset, ...)` addresses it individually.
    function withdrawAllInKind(address to) external onlyOwner nonReentrant {
        address usdc = factory.usdc();
        _tryWithdrawAll(usdc, to);
        for (uint256 i; i < _components.length; ++i) _tryWithdrawAll(_components[i].token, to);
    }

    function _tryWithdrawAll(address asset, address to) internal {
        (bool okb, bytes memory rb) = asset.staticcall(abi.encodeCall(IERC20Min.balanceOf, (address(this))));
        if (!okb || rb.length < 32) return;
        uint256 bal = abi.decode(rb, (uint256));
        if (bal == 0) return;
        (bool ok, bytes memory ret) = asset.call(abi.encodeWithSignature("transfer(address,uint256)", to, bal));
        if (ok && (ret.length == 0 || abi.decode(ret, (bool)))) emit Withdrawn(asset, bal, to);
    }

    // ================================================================ configuration

    /// @inheritdoc IIndexVault
    function setComponents(Component[] calldata comps) external onlyOwner {
        uint256 n = comps.length;
        if (n == 0 || n > MAX_COMPONENTS) revert BadComponents();
        uint256 sum;
        address usdc = factory.usdc();
        for (uint256 i; i < n; ++i) {
            address t = comps[i].token;
            if (t == usdc || factory.capOf(t) == 0) revert TokenNotAllowed(t);
            for (uint256 j; j < i; ++j) if (comps[j].token == t) revert BadComponents();
            sum += comps[i].targetWeightBps;
        }
        if (sum != 10_000) revert WeightsMustSumTo10000();
        delete _components;
        for (uint256 i; i < n; ++i) _components.push(comps[i]);
        emit ComponentsUpdated();
    }

    /// @inheritdoc IIndexVault
    function setRules(Rules calldata r) external onlyOwner {
        if (r.maxSlippageBps > MAX_SLIPPAGE_CAP_BPS) revert SlippageCapExceeded(r.maxSlippageBps);
        if (r.driftThresholdBps > 10_000) revert InvalidRules();
        rules = r;
        emit RulesUpdated();
    }

    // ================================================================ views

    function components() external view returns (Component[] memory) {
        return _components;
    }

    function currentWeights() external view returns (uint16[] memory w) {
        uint256 len = _components.length;
        w = new uint16[](len);
        (uint256[] memory values, uint256 total,) = _valuesBestEffort();
        if (total == 0) return w;
        for (uint256 i; i < len; ++i) w[i] = uint16(values[i] * 10_000 / total);
    }

    /// @notice Sum of USDC and the components that are FRESH. `allFresh == false` means the sum is partial.
    function totalValue() external view returns (uint256 value, bool allFresh) {
        (, uint256 total, bool fresh) = _valuesBestEffort();
        return (total + IERC20Min(factory.usdc()).balanceOf(address(this)), fresh);
    }

    function _valuesBestEffort() internal view returns (uint256[] memory values, uint256 total, bool allFresh) {
        uint256 len = _components.length;
        values = new uint256[](len);
        allFresh = true;
        ISessionOracle oracle = factory.oracle();
        for (uint256 i; i < len; ++i) {
            address t = _components[i].token;
            (RefusalKind k,, uint256 price) = _classify(oracle, t);
            if (k != RefusalKind.NONE) {
                allFresh = false;
                continue;
            }
            values[i] = _valueOf(t, IERC20Min(t).balanceOf(address(this)), price);
            total += values[i];
        }
    }

    /// @notice Display only. Never used in valuation or trading.
    function scaledHoldings() external view returns (uint256[] memory out) {
        uint256 len = _components.length;
        out = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            address t = _components[i].token;
            uint256 bal = IERC20Min(t).balanceOf(address(this));
            (bool ok, bytes memory ret) = t.staticcall(abi.encodeWithSignature("uiMultiplier()"));
            out[i] = (ok && ret.length >= 32) ? bal * abi.decode(ret, (uint256)) / 1e18 : bal;
        }
    }

    /// @inheritdoc IIndexVault
    function rebalanceStatus()
        external
        view
        returns (bool possible, Refusal[] memory refusals, uint64 nextEligibleAt, uint16 maxDriftBps)
    {
        Evaluation memory e = _evaluate(Action.REBALANCE);
        refusals = new Refusal[](e.n);
        for (uint256 i; i < e.n; ++i) refusals[i] = e.refusals[i];
        nextEligibleAt = lastRebalanceAt == 0 ? 0 : uint64(uint256(lastRebalanceAt) + rules.minRebalanceInterval);
        return (e.n == 0, refusals, nextEligibleAt, e.maxDriftBps);
    }

    function refusalCount() external view returns (uint256) {
        return _refusals;
    }

    function rebalanceCount() external view returns (uint256) {
        return _rebalances;
    }

    // ================================================================ token helpers

    function _pull(address token, address from, uint256 amount) internal {
        (bool ok, bytes memory ret) =
            token.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", from, address(this), amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transferFrom failed");
    }

    function _push(address token, address to, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "transfer failed");
    }

    function _approve(address token, address spender, uint256 amount) internal {
        (bool ok, bytes memory ret) = token.call(abi.encodeWithSignature("approve(address,uint256)", spender, amount));
        require(ok && (ret.length == 0 || abi.decode(ret, (bool))), "approve failed");
    }
}
