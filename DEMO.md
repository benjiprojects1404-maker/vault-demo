# Mock 2 demo: SavingsVault

```bash
git checkout mock-2-demo
forge test --match-contract SavingsVaultDemoTest -vv     # the three bugs, proved
forge test --match-contract SavingsVaultFixedTest -vv    # the same attacks, refused by the fix
```

The bug tests **pass because the bugs are real**. The fixed contract is `src/SavingsVaultFixed.sol` (changes marked `FIX`).

| # | Severity | Say it | Test | Fix |
|---|---|---|---|---|
| 1 | Critical | `rescueTokens` has no `onlyOwner`. Bob, a stranger, "rescues" the vault's own token and takes alice's 5,000. The vault is empty. | `test_bug1_strangerTakesAllDeposits` | `onlyOwner` |
| 2 | High | Even the owner shouldn't be able to rescue the asset: that's customer money, and it means trusting one key. | `test_bug2_ownerCanTakeCustomerMoney` | `require(token != asset())` |
| 3 | Medium | The cap is only in `maxDeposit`. `maxMint` isn't overridden, so `mint` lets 2,000 in past a 500 cap. | `test_bug3_mintSkipsTheCap` | override `maxMint` |

**Are the existing tests enough?** No. They never call `rescueTokens` as a stranger, never rescue the asset
itself, and never use `mint` near the cap. The rescue test only checks the happy path.

**Good bits to mention:** `_decimalsOffset` of 6 (stops the first-depositor inflation trick), SafeERC20,
`onlyOwner` on `setDepositCap`, events on every admin action.
