// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YieldVault} from "../src/YieldVault.sol";
import {MockToken} from "../src/Tokens.sol";

contract YieldVaultTest is Test {
    MockToken usd;
    YieldVault vault;
    address treasury = makeAddr("treasury");
    address alice = makeAddr("alice");
    address desk = makeAddr("desk"); // the bank's trading desk

    function setUp() public {
        usd = new MockToken();
        vault = new YieldVault(usd, treasury, 100_000e18);
        usd.mint(alice, 50_000e18);
        usd.mint(desk, 50_000e18);
        vm.prank(alice);
        usd.approve(address(vault), type(uint256).max);
    }

    function test_depositAndRedeem() public {
        vm.startPrank(alice);
        uint256 shares = vault.deposit(1_000e18, alice);
        assertEq(vault.redeem(shares, alice, alice), 1_000e18);
        vm.stopPrank();
    }

    function test_harvestTakesTenPercentOfProfit() public {
        vm.prank(alice);
        vault.deposit(10_000e18, alice);
        vault.harvest(); // sets the starting point

        vm.prank(desk);
        usd.transfer(address(vault), 1_000e18); // 1,000 profit

        vault.harvest();
        uint256 treasuryValue = vault.convertToAssets(vault.balanceOf(treasury));
        assertApproxEqAbs(treasuryValue, 100e18, 1e6); // 10% of 1,000
    }

    function test_depositCapIsEnforced() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(100_001e18, alice);
    }

    function test_onlyOwnerCanHarvest() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.harvest();
    }
}
