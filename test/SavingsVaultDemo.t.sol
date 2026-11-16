// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SavingsVault} from "../src/SavingsVault.sol";
import {SavingsVaultFixed} from "../src/SavingsVaultFixed.sol";
import {MockToken} from "../src/Tokens.sol";

/// Demo: each bug in SavingsVault, proved. Each test PASSES because the bug is real.
/// Run: forge test --match-contract SavingsVaultDemoTest -vv
contract SavingsVaultDemoTest is Test {
    MockToken usd;
    SavingsVault vault;
    address alice = makeAddr("alice"); // honest customer
    address bob = makeAddr("bob");     // stranger / attacker

    function setUp() public {
        usd = new MockToken();
        vault = new SavingsVault(usd, 1_000_000e18); // this test contract is the owner
        usd.mint(alice, 10_000e18);
        vm.prank(alice);
        usd.approve(address(vault), type(uint256).max);
    }

    /// Bug 1 (Critical): rescueTokens has no onlyOwner.
    /// A stranger "rescues" the vault's own asset and takes every customer's deposit.
    function test_bug1_strangerTakesAllDeposits() public {
        vm.prank(alice);
        vault.deposit(5_000e18, alice);              // alice saves 5,000

        vm.prank(bob);
        vault.rescueTokens(address(usd), bob);       // bob isn't the owner, and it works

        assertEq(usd.balanceOf(bob), 5_000e18, "bob took alice's 5,000");
        assertEq(vault.totalAssets(), 0, "the vault is empty");
        assertEq(vault.maxWithdraw(alice), 0, "alice can't get anything back");
    }

    /// Bug 2 (High): even the owner shouldn't be able to rescue the asset itself.
    /// Rescue is for stray tokens; letting the owner take the asset means customers must trust one key.
    function test_bug2_ownerCanTakeCustomerMoney() public {
        vm.prank(alice);
        vault.deposit(5_000e18, alice);

        vault.rescueTokens(address(usd), address(this)); // the owner, "rescuing" the asset

        assertEq(usd.balanceOf(address(this)), 5_000e18, "owner took customer deposits");
    }

    /// Bug 3 (Medium): the cap is only in maxDeposit. maxMint isn't overridden, so mint() ignores the cap.
    function test_bug3_mintSkipsTheCap() public {
        vault.setDepositCap(500e18);                     // compliance cap: 500
        assertEq(vault.maxDeposit(alice), 500e18);       // deposit respects it...

        uint256 shares = vault.convertToShares(2_000e18);
        vm.prank(alice);
        vault.mint(shares, alice);                       // ...but mint lets 2,000 in

        assertGt(vault.totalAssets(), 500e18, "vault is over its cap");
    }
}

/// The same three attacks against the fixed vault: every one is now refused.
contract SavingsVaultFixedTest is Test {
    MockToken usd;
    SavingsVaultFixed vault;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        usd = new MockToken();
        vault = new SavingsVaultFixed(usd, 1_000_000e18);
        usd.mint(alice, 10_000e18);
        vm.prank(alice);
        usd.approve(address(vault), type(uint256).max);
        vm.prank(alice);
        vault.deposit(5_000e18, alice);
    }

    function test_fix1_strangerCantRescue() public {
        vm.prank(bob);
        vm.expectRevert(bytes("not owner"));
        vault.rescueTokens(address(usd), bob);
    }

    function test_fix2_ownerCantRescueTheAsset() public {
        vm.expectRevert(bytes("can't rescue the asset"));
        vault.rescueTokens(address(usd), address(this));
    }

    function test_fix2_ownerCanStillRescueStrayTokens() public {
        MockToken stray = new MockToken();
        stray.mint(address(vault), 5e18);
        vault.rescueTokens(address(stray), address(this));
        assertEq(stray.balanceOf(address(this)), 5e18);
    }

    function test_fix3_mintRespectsTheCap() public {
        vault.setDepositCap(5_500e18);                   // room for 500 more
        uint256 shares = vault.convertToShares(2_000e18);
        vm.prank(alice);
        vm.expectRevert();                               // ERC4626ExceededMaxMint
        vault.mint(shares, alice);
    }
}
