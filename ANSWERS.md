# Mock 5 (YieldVault): answers

Don't read this until you've tried the task on the `mock-5` branch.

Run the proofs: `forge test --match-contract YieldVaultAnswersTest -vv`
The fixed contract is `src/YieldVaultFixed.sol` (every change is marked `FIX`).

## What it does (step 1)

A managed ERC-4626 vault. Profit arrives as plain transfers from the bank's desk. `harvest()` (owner only)
compares `totalAssets()` with the value at the last harvest, takes 10% of any rise as a fee, and pays it by
minting new shares to the treasury, which dilutes everyone else by exactly the fee. Deposits are capped
through `maxDeposit`.

## Are the tests enough? (step 2)

No. The fee test only has profit between two harvests, never a deposit, a withdrawal or a loss. Nothing
calls `mint()`. Nothing checks that a customer who deposits and does nothing else keeps their money. Every
bug below lives in those gaps.

## Findings (step 3), most severe first

### 1. Deposits are charged as profit (High)

`harvest()` takes "profit" as `totalAssets() - lastTotalAssets`, but deposits raise `totalAssets()` too. If
Bob deposits 50,000 between harvests, the treasury mints itself 5,000 worth of shares. That comes out of
**every** customer, Bob included, and it happens every day the product takes deposits. (Withdrawals do the
reverse and hide real profit, so the bank under-charges.)

- Proof: `test_bug1_feeOnDeposits`.
- Fix: move the baseline with customer flows (`lastTotalAssets += assets` in `_deposit`, `-= assets` in
  `_withdraw`). Better still, measure profit **per share** (price per share vs. the last harvest), which
  deposits and withdrawals can't affect.
- The usual suspect: **"accounting that assumes nothing else changes"**. Ask "what else moves this number?"

### 2. No high-water mark: recovering a loss is charged again (Medium)

After a loss, `harvest()` sets `lastTotalAssets` to the lower total. When the desk earns it back, the
recovery counts as profit and the treasury takes 10%, though customers are only back to where they started.

- Proof: `test_bug2_feeOnRecoveredLoss` (lose 2,000, recover 2,000, fee 200).
- Fix: only raise the baseline, never lower it on a loss (a high-water mark). Again, per-share is cleaner.

### 3. `mint()` bypasses the deposit cap (Medium)

`maxDeposit` is capped, but `maxMint` isn't overridden. OpenZeppelin's `mint()` checks `maxMint`, which
still returns "unlimited", so `mint(500,000 shares)` goes straight past the 100,000 cap. The **pairs rule**:
deposit/mint, withdraw/redeem, maxDeposit/maxMint, maxWithdraw/maxRedeem.

- Proof: `test_bug3_mintBypassesCap`.
- Fix: `maxMint(r) = previewDeposit(maxDeposit(r))`.

### Also worth saying (no test needed)

- **Timing games:** `harvest()` is once a day, so someone can deposit just before profit lands and withdraw
  just after harvest, taking yield they didn't wait for. Fixes: harvest more often, or stream profit in
  over time.
- **Owner trust:** one owner key controls the cap and the fee timing. Use a multisig.
- **Fee maths is right:** `feeAssets * (supply + 1) / (total - feeAssets + 1)` gives shares worth exactly
  `feeAssets` after minting (`test_fixed_stillTakesTenPercentOfRealProfit` checks it). Worth saying out loud
  that you checked it rather than assumed it.

## The one-line lesson

When a contract measures "profit" as a change in a total, list everything else that changes that total
(deposits, withdrawals, losses, donations) and check that each one is handled.
