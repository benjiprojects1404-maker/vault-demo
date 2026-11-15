# Partner Rewards Vault: technical assessment

`src/RewardsVault.sol` is an ERC-4626 partner savings vault for a neobank (OpenZeppelin 5, Foundry).
The bank deploys one vault per partner, holding that partner's token. Each week the partner adds rewards in
its loyalty token, shared between depositors by their shares. Rewards are paid on every deposit and
withdrawal, or any time with `claim()`.

The first partner to launch is CASH, whose token behaves like `FeeToken` in `src/Tokens.sol`. Vault shares
are ordinary ERC-20 tokens, so customers can move them between their own wallets.

## Setup

```bash
./setup.sh    # downloads forge-std and OpenZeppelin, then runs the tests
```

## Task (about 45 minutes)

1. Review `src/RewardsVault.sol`. Talk us through what it does.
2. The existing tests pass. Are they enough? What's missing?
3. Find any issues. For each one: explain the impact, prove it with a Foundry test, and propose a fix.
