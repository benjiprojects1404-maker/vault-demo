# Managed Yield Vault: technical assessment

`src/YieldVault.sol` is an ERC-4626 managed savings vault for a neobank (OpenZeppelin 5, Foundry).
The bank's trading desk earns yield on the deposits and sends the profit back into the vault. Once a day the
bank calls `harvest()`, which takes a 10% performance fee on the profit by minting shares to the treasury.
While the product is new, total deposits are capped at 100,000.

## Setup

```bash
./setup.sh    # downloads forge-std and OpenZeppelin, then runs the tests
```

## Task (about 45 minutes)

1. Review `src/YieldVault.sol`. Talk us through what it does.
2. The existing tests pass. Are they enough? What's missing?
3. Find any issues. For each one: explain the impact, prove it with a Foundry test, and propose a fix.
