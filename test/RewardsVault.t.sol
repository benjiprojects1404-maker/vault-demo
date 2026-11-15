// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RewardsVault} from "../src/RewardsVault.sol";
import {MockToken} from "../src/Tokens.sol";

contract RewardsVaultTest is Test {
    MockToken usd;
    MockToken loyalty;
    RewardsVault vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        usd = new MockToken();
        loyalty = new MockToken();
        vault = new RewardsVault(usd, loyalty, "Partner Saver", "pSAV");
        address[2] memory people = [alice, bob];
        for (uint256 i; i < 2; ++i) {
            usd.mint(people[i], 10_000e18);
            vm.prank(people[i]);
            usd.approve(address(vault), type(uint256).max);
        }
        loyalty.mint(address(this), 1_000_000e18);
        loyalty.approve(address(vault), type(uint256).max);
    }

    function test_rewardsSplitByShares() public {
        vm.prank(alice);
        vault.deposit(3_000e18, alice);
        vm.prank(bob);
        vault.deposit(1_000e18, bob);
        vault.addRewards(400e18);

        vm.prank(alice);
        vault.claim();
        vm.prank(bob);
        vault.claim();
        assertEq(loyalty.balanceOf(alice), 300e18);
        assertEq(loyalty.balanceOf(bob), 100e18);
    }

    function test_withdrawPaysRewards() public {
        vm.startPrank(alice);
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
        vault.addRewards(50e18);
        vm.prank(alice);
        vault.withdraw(1_000e18, alice, alice);
        assertEq(loyalty.balanceOf(alice), 50e18);
        assertEq(usd.balanceOf(alice), 10_000e18);
    }

    function test_noDoubleClaim() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);
        vault.addRewards(50e18);
        vm.startPrank(alice);
        vault.claim();
        vault.claim();
        vm.stopPrank();
        assertEq(loyalty.balanceOf(alice), 50e18);
    }

    function test_onlyOwnerAddsRewards() public {
        vm.prank(alice);
        vault.deposit(1_000e18, alice);
        vm.prank(alice);
        vm.expectRevert();
        vault.addRewards(1e18);
    }
}
