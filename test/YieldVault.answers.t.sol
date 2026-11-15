// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {YieldVaultFixed} from "../src/YieldVaultFixed.sol";
import {MockToken} from "../src/Tokens.sol";

/// Proofs for ANSWERS.md. Each bug is shown on YieldVault, then shown fixed on YieldVaultFixed.
contract YieldVaultAnswersTest is Test {
    MockToken usd;
    YieldVault vault;
    YieldVault fixedVault; // YieldVaultFixed, same functions
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address desk = makeAddr("desk");

    function setUp() public {
        usd = new MockToken();
        vault = new YieldVault(usd, treasury, 100_000e18);
        fixedVault = YieldVault(address(new YieldVaultFixed(usd, treasury, 100_000e18)));
        address[2] memory people = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            usd.mint(people[i], 1_000_000e18);
            vm.startPrank(people[i]);
            usd.approve(address(vault), type(uint256).max);
            usd.approve(address(fixedVault), type(uint256).max);
            vm.stopPrank();
        }
        usd.mint(desk, 1_000_000e18);
    }

    function _treasuryValue(YieldVault v) internal view returns (uint256) {
        return v.convertToAssets(v.balanceOf(treasury));
    }

    // ---------------------------------------------------------------- Bug 1: fee charged on new deposits
    // harvest() treats ANY rise in totalAssets as profit. A customer deposit between harvests is a rise, so the
    // treasury takes 10% of it, out of every customer's pocket.
    function _depositBetweenHarvests(YieldVault v) internal {
        vm.prank(alice);
        v.deposit(10_000e18, alice);
        v.harvest();                 // starting point
        vm.prank(bob);
        v.deposit(50_000e18, bob);   // a new customer: no profit at all
        v.harvest();
    }

    function test_bug1_feeOnDeposits() public {
        _depositBetweenHarvests(vault);
        assertApproxEqRel(_treasuryValue(vault), 5_000e18, 0.001e18, "treasury took 10% of bob's deposit");
        assertLt(vault.convertToAssets(vault.balanceOf(bob)), 46_000e18, "bob lost money on day one");
    }

    function test_bug1_fixed() public {
        _depositBetweenHarvests(fixedVault);
        assertEq(fixedVault.balanceOf(treasury), 0, "no profit, no fee");
    }

    // ---------------------------------------------------------------- Bug 2: no high-water mark
    // After a loss, harvest() lowers the baseline. When the desk earns the loss back, that recovery is charged
    // as "profit" even though customers are only back where they started.
    function _lossThenRecovery(YieldVault v) internal {
        vm.prank(alice);
        v.deposit(10_000e18, alice);
        v.harvest();
        vm.prank(address(v));
        usd.transfer(desk, 2_000e18);   // the desk loses 2,000
        v.harvest();
        vm.prank(desk);
        usd.transfer(address(v), 2_000e18); // and earns it back
        v.harvest();
    }

    function test_bug2_feeOnRecoveredLoss() public {
        _lossThenRecovery(vault);
        assertApproxEqRel(_treasuryValue(vault), 200e18, 0.001e18, "fee on money that was only recovered");
    }

    function test_bug2_fixed() public {
        _lossThenRecovery(fixedVault);
        assertEq(fixedVault.balanceOf(treasury), 0);
    }

    // ---------------------------------------------------------------- Bug 3: mint() ignores the cap
    // maxDeposit is capped but maxMint isn't overridden, so OpenZeppelin's mint() check passes for any amount.
    function test_bug3_mintBypassesCap() public {
        vm.prank(alice);
        vault.mint(500_000e18, alice); // 5x the 100,000 cap
        assertEq(vault.totalAssets(), 500_000e18);
    }

    function test_bug3_fixed() public {
        vm.prank(alice);
        vm.expectRevert();
        fixedVault.mint(500_000e18, alice);
    }

    // ---------------------------------------------------------------- the fix still charges real profit
    function test_fixed_stillTakesTenPercentOfRealProfit() public {
        vm.prank(alice);
        fixedVault.deposit(10_000e18, alice);
        fixedVault.harvest();
        vm.prank(bob);
        fixedVault.deposit(5_000e18, bob);       // ignored
        vm.prank(desk);
        usd.transfer(address(fixedVault), 1_500e18); // real profit
        fixedVault.harvest();
        assertApproxEqRel(_treasuryValue(fixedVault), 150e18, 0.001e18);
    }
}
