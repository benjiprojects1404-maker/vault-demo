// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RewardsVault} from "../src/RewardsVault.sol";
import {RewardsVaultFixed} from "../src/RewardsVaultFixed.sol";
import {MockToken, FeeToken} from "../src/Tokens.sol";

/// Proofs for ANSWERS.md. Each bug is shown on RewardsVault, then shown fixed on RewardsVaultFixed.
contract RewardsVaultAnswersTest is Test {
    MockToken usd;
    MockToken loyalty;
    FeeToken cash;
    address alice = makeAddr("alice");
    address alice2 = makeAddr("alice2"); // alice's second wallet
    address alice3 = makeAddr("alice3");
    address bob = makeAddr("bob");

    function setUp() public {
        usd = new MockToken();
        loyalty = new MockToken();
        cash = new FeeToken();
        loyalty.mint(address(this), 1_000_000e18);
    }

    function _vault(bool fixedOne, address assetToken) internal returns (RewardsVault v) {
        v = fixedOne
            ? RewardsVault(address(new RewardsVaultFixed(MockToken(assetToken), loyalty, "Partner Saver", "pSAV")))
            : new RewardsVault(MockToken(assetToken), loyalty, "Partner Saver", "pSAV");
        loyalty.approve(address(v), type(uint256).max);
        address[2] memory people = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            MockToken(assetToken).mint(people[i], 10_000e18);
            vm.prank(people[i]);
            MockToken(assetToken).approve(address(v), type(uint256).max);
        }
    }

    function _twoDepositorsAndRewards(RewardsVault v) internal {
        vm.prank(alice);
        v.deposit(1_000e18, alice);
        vm.prank(bob);
        v.deposit(1_000e18, bob);
        v.addRewards(200e18); // 100 each
    }

    // ---------------------------------------------------------------- Bug 1a: rewards claimed again after a transfer
    // Share transfers don't touch rewardDebt. The receiving wallet has debt 0, so it can claim every reward ever
    // paid on those shares, even though alice already claimed them. Pass the shares on and claim again.
    function test_bug1_transferAndClaimAgain() public {
        RewardsVault v = _vault(false, address(usd));
        _twoDepositorsAndRewards(v);

        vm.startPrank(alice);
        v.claim();                                  // 100, fair
        v.transfer(alice2, v.balanceOf(alice));
        vm.stopPrank();
        vm.prank(alice2);
        v.claim();                                  // another 100: bob's

        assertEq(loyalty.balanceOf(alice) + loyalty.balanceOf(alice2), 200e18, "alice took the whole pot");
        vm.prank(bob);
        vm.expectRevert();                          // nothing left for bob
        v.claim();
    }

    // ---------------------------------------------------------------- Bug 1b: the sender gets stuck
    // After sending shares away, alice's rewardDebt is bigger than balance * acc, so pendingRewards underflows.
    // Every withdraw calls _claim first, so she can't take out the shares she still has.
    function test_bug1_senderCantWithdraw() public {
        RewardsVault v = _vault(false, address(usd));
        _twoDepositorsAndRewards(v);
        vm.startPrank(alice);
        v.claim();
        v.transfer(alice3, v.balanceOf(alice) / 2);
        vm.expectRevert();                          // arithmetic underflow
        v.withdraw(100e18, alice, alice);
        vm.stopPrank();
    }

    function test_bug1_fixed() public {
        RewardsVault v = _vault(true, address(usd));
        _twoDepositorsAndRewards(v);
        vm.startPrank(alice);
        v.claim();
        v.transfer(alice2, v.balanceOf(alice) / 2);
        v.withdraw(100e18, alice, alice);           // works
        vm.stopPrank();
        vm.prank(alice2);
        v.claim();                                  // nothing extra
        assertEq(loyalty.balanceOf(alice) + loyalty.balanceOf(alice2), 100e18);
        vm.prank(bob);
        v.claim();
        assertEq(loyalty.balanceOf(bob), 100e18, "bob still gets his share");
    }

    // ---------------------------------------------------------------- Bug 2: fee-on-transfer asset (CASH)
    // Shares are priced for the full `assets`, but 1% is burned on the way in. Each new deposit dilutes the
    // customers already in the vault by the newcomer's fee.
    function test_bug2_feeTokenDilutesExistingCustomers() public {
        RewardsVault v = _vault(false, address(cash));
        vm.prank(alice);
        v.deposit(1_000e18, alice);                 // 990 arrives
        uint256 aliceBefore = v.convertToAssets(v.balanceOf(alice));
        vm.prank(bob);
        v.deposit(5_000e18, bob);                   // 4,950 arrives, bob gets shares for 5,000
        uint256 aliceAfter = v.convertToAssets(v.balanceOf(alice));
        assertLt(aliceAfter, aliceBefore - 7e18, "alice paid part of bob's fee");
    }

    function test_bug2_fixed() public {
        RewardsVault v = _vault(true, address(cash));
        vm.prank(alice);
        vm.expectRevert(bytes("fee-on-transfer tokens not supported"));
        v.deposit(1_000e18, alice);
    }
}
