// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title YieldVault
/// @notice Managed savings product for a neobank. The bank's trading desk earns yield on the deposits and sends
///         the profit back into the vault. Once a day the bank calls harvest(), which takes a 10% performance fee
///         on the profit since the last harvest by minting new shares to the treasury.
///         While the product is new, total deposits are capped.
contract YieldVault is ERC4626, Ownable {
    using Math for uint256;

    uint256 public constant PERFORMANCE_FEE_BPS = 1_000; // 10% of profit
    uint256 private constant BPS = 10_000;

    address public immutable treasury;
    uint256 public depositCap;
    uint256 public lastTotalAssets; // total assets at the last harvest

    event Harvest(uint256 profit, uint256 feeShares);

    constructor(IERC20 asset_, address treasury_, uint256 depositCap_)
        ERC20("Managed Yield", "mYLD")
        ERC4626(asset_)
        Ownable(msg.sender)
    {
        treasury = treasury_;
        depositCap = depositCap_;
    }

    function setDepositCap(uint256 cap) external onlyOwner {
        depositCap = cap;
    }

    /// @notice How much more can be deposited before the cap is reached.
    function maxDeposit(address) public view override returns (uint256) {
        uint256 total = totalAssets();
        return total >= depositCap ? 0 : depositCap - total;
    }

    /// @notice Takes the performance fee on profit since the last harvest.
    function harvest() external onlyOwner {
        uint256 total = totalAssets();
        if (lastTotalAssets == 0) {
            lastTotalAssets = total; // first harvest just sets the starting point
            return;
        }
        if (total > lastTotalAssets) {
            uint256 profit = total - lastTotalAssets;
            uint256 feeAssets = profit.mulDiv(PERFORMANCE_FEE_BPS, BPS);
            // Shares worth `feeAssets` after they're minted.
            uint256 feeShares = feeAssets.mulDiv(totalSupply() + 1, total - feeAssets + 1);
            _mint(treasury, feeShares);
            emit Harvest(profit, feeShares);
        }
        lastTotalAssets = total;
    }
}
