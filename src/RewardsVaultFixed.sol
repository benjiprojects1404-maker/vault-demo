// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title RewardsVault
/// @notice Partner savings vault. The neobank deploys one vault per partner, holding that partner's token. On top
///         of the vault's own yield, the partner pays weekly rewards in its loyalty token, shared between
///         depositors in proportion to their shares. Rewards are paid automatically on every deposit and
///         withdrawal, or any time with claim().
contract RewardsVaultFixed is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    uint256 private constant ACC = 1e18;

    IERC20 public immutable rewardToken;
    uint256 public accRewardPerShare; // rewards per share so far, scaled by 1e18
    mapping(address => uint256) public rewardDebt;

    event RewardsAdded(uint256 amount);
    event Claimed(address indexed user, uint256 amount);

    constructor(IERC20 asset_, IERC20 rewardToken_, string memory name_, string memory symbol_)
        ERC20(name_, symbol_)
        ERC4626(asset_)
        Ownable(msg.sender)
    {
        rewardToken = rewardToken_;
    }

    /// @notice The partner tops up this week's rewards.
    function addRewards(uint256 amount) external onlyOwner {
        require(totalSupply() > 0, "no depositors");
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        accRewardPerShare += amount * ACC / totalSupply();
        emit RewardsAdded(amount);
    }

    function pendingRewards(address user) public view returns (uint256) {
        return balanceOf(user) * accRewardPerShare / ACC - rewardDebt[user];
    }

    function claim() external {
        _claim(msg.sender);
    }

    function _claim(address user) internal {
        uint256 owed = pendingRewards(user);
        rewardDebt[user] = balanceOf(user) * accRewardPerShare / ACC;
        if (owed > 0) {
            rewardToken.safeTransfer(user, owed);
            emit Claimed(user, owed);
        }
    }

    /// @dev FIX 2: refuse tokens that deliver less than was sent (fee-on-transfer). Shares were priced for
    ///      `assets`, so anything less would make existing customers pay the newcomer's transfer fee.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _claim(receiver);
        IERC20 token = IERC20(asset());
        uint256 before = token.balanceOf(address(this));
        token.safeTransferFrom(caller, address(this), assets);
        require(token.balanceOf(address(this)) - before == assets, "fee-on-transfer tokens not supported");
        _mint(receiver, shares);
        emit Deposit(caller, receiver, assets, shares);
        rewardDebt[receiver] = balanceOf(receiver) * accRewardPerShare / ACC;
    }

    /// @dev FIX 1: share transfers settle rewards for both sides, like deposits and withdrawals do.
    function _update(address from, address to, uint256 value) internal override {
        bool isTransfer = from != address(0) && to != address(0);
        if (isTransfer) {
            _claim(from);
            _claim(to);
        }
        super._update(from, to, value);
        if (isTransfer) {
            rewardDebt[from] = balanceOf(from) * accRewardPerShare / ACC;
            rewardDebt[to] = balanceOf(to) * accRewardPerShare / ACC;
        }
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        _claim(owner);
        super._withdraw(caller, receiver, owner, assets, shares);
        rewardDebt[owner] = balanceOf(owner) * accRewardPerShare / ACC;
    }
}
