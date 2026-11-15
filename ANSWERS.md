# Mock 6 (RewardsVault): answers

Don't read this until you've tried the task on the `mock-6` branch.

Run the proofs: `forge test --match-contract RewardsVaultAnswersTest -vv`
The fixed contract is `src/RewardsVaultFixed.sol` (every change is marked `FIX`).

## What it does (step 1)

An ERC-4626 vault with a second income stream: the owner adds loyalty-token rewards, spread over all shares
with the standard "reward per share" accumulator (`accRewardPerShare`). Each user's `rewardDebt` records the
part of the accumulator they've already been paid for; `pending = balance × acc − rewardDebt`. Deposits and
withdrawals settle rewards first, then reset the debt to the new balance.

## Are the tests enough? (step 2)

No. Nothing moves shares with `transfer`, nothing uses the CASH token the README says is launching first,
and nothing adds rewards and then has someone join or leave just around it. Both real bugs sit there.

## Findings (step 3), most severe first

### 1. Share transfers don't settle rewards: the pot can be drained, and senders get stuck (Critical)

The accumulator only works if `rewardDebt` is updated **every time a balance changes**. Deposits and
withdrawals do that, but plain share transfers (`transfer`, `transferFrom`) don't: `_update` isn't
overridden.

- **Theft:** alice claims her 100, sends her shares to a second wallet (debt 0), and that wallet claims the
  same rewards again: bob's 100. Repeat with more wallets until the pot is empty. Bob's claim then reverts.
  Proof: `test_bug1_transferAndClaimAgain`.
- **Stuck funds:** the *sender* now has a debt bigger than `balance × acc`, so `pendingRewards` underflows,
  and every `withdraw` calls `_claim` first, so she can't take out the shares she still has. Proof:
  `test_bug1_senderCantWithdraw`.
- Fix: override `_update` to settle both sides before a transfer and reset both debts after it.
- The usual suspect: **"every path that changes a balance"**. Deposit, withdraw, mint, redeem **and
  transfer** all move shares.

### 2. Fee-on-transfer asset: newcomers' fees are paid by existing customers (High)

CASH burns 1% on every transfer (`FeeToken`). ERC-4626 prices the shares for the full `assets`, then
OpenZeppelin pulls the tokens, and only 99% arrives. The new depositor gets shares for money that never
arrived, so everyone already in the vault is diluted by the newcomer's fee, on every deposit.

- Proof: `test_bug2_feeTokenDilutesExistingCustomers` (bob's 5,000 deposit costs alice about 8).
- Fix: measure what actually arrived and refuse the deposit if it's less (the fix here), or price shares on
  the amount received. Refusing is cleaner, because ERC-4626's previews can't be honest about a token that
  takes a cut. Either way, say: "I'd confirm which tokens the vault will hold." That's the **odd tokens**
  usual suspect, and the README told you about CASH.

### Also worth saying (no test needed)

- **Just-in-time rewards:** rewards go to whoever holds shares at the moment `addRewards` runs. Someone who
  sees it coming can deposit just before and withdraw just after, taking a share of a week's rewards for a
  few minutes' deposit. Fixes: stream rewards over the week, or pay only for shares held through the period.
- **Rounding dust:** `amount * 1e18 / totalSupply()` rounds down, so a little of each top-up is never paid
  out. Fine, but say you noticed.
- **Configuration:** if the reward token were ever the same as the asset, rewards would be counted as vault
  assets *and* paid out as rewards. Worth a check in the constructor.
- **Good bits:** CEI in `_claim` (debt updated before the transfer), SafeERC20, owner-only `addRewards`, and
  the `require(totalSupply() > 0)` that stops rewards being lost when nobody's in.

## The one-line lesson

With any per-user accounting (rewards, debts, locks), list every way a balance can change, transfers
included, and check that each one updates the books. With any external token, ask which tokens.
