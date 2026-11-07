// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISessionOracle} from "../ISessionOracle.sol";

/// @notice TEST ONLY.
contract MockToken {
    string public symbol;
    uint8 public immutable decimals;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public uiMultiplier = 1e18;
    uint256 public effectiveAt;
    bool public blockTransfers;
    mapping(address => bool) public blocked;

    constructor(string memory s, uint8 d) {
        symbol = s;
        decimals = d;
    }

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function setMultiplier(uint256 m) external {
        uiMultiplier = m;
    }

    function setEffectiveAt(uint256 t) external {
        effectiveAt = t;
    }

    function setBlocked(address a, bool b) external {
        blocked[a] = b;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        return _move(msg.sender, to, a);
    }

    function transferFrom(address f, address to, uint256 a) external returns (bool) {
        uint256 al = allowance[f][msg.sender];
        if (al != type(uint256).max) allowance[f][msg.sender] = al - a;
        return _move(f, to, a);
    }

    function _move(address f, address t, uint256 a) internal returns (bool) {
        require(!blocked[t], "blocked");
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }
}

/// @notice TEST ONLY. Pays out whatever it was told to, from its own inventory.
contract MockRouter {
    bool public reverts;

    function setReverts(bool v) external {
        reverts = v;
    }

    function swap(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOut, address to) external {
        require(!reverts, "router down");
        MockToken(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        MockToken(tokenOut).transfer(to, amountOut);
    }
}

/// @notice TEST ONLY. A session oracle whose verdict per token is set directly.
contract MockOracle is ISessionOracle {
    mapping(address => Mark) public marks;
    bool public reverts;

    function set(address token, int256 price, Session s, Cause c) external {
        Mark storage m = marks[token];
        m.price = price;
        m.session = s;
        m.cause = c;
    }

    function fresh(address token, int256 price) external {
        Mark storage m = marks[token];
        m.price = price;
        m.session = Session.FRESH;
        m.cause = Cause.NONE;
    }

    function setReverts(bool v) external {
        reverts = v;
    }

    function markOf(address token) external view returns (Mark memory) {
        require(!reverts, "oracle down");
        return marks[token];
    }

    function isFresh(address token) external view returns (bool) {
        return marks[token].session == Session.FRESH;
    }

    function marksOf(address[] calldata tokens) external view returns (Mark[] memory out) {
        out = new Mark[](tokens.length);
        for (uint256 i; i < tokens.length; ++i) out[i] = marks[tokens[i]];
    }
}
