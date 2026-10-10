# Infer token tests

Run `forge build --offline` and `forge test --offline` from the repository root.
All imports are already vendored; the suite needs no RPC, environment variables,
additional packages, or changes to Foundry configuration.

The expected supply is independently specified as `1_000_000_000 * 10 ** 18`.
Fixtures move constructor-minted tokens through the public API; they do not write
token storage or manufacture balances with cheatcodes.

| File | Coverage |
| --- | --- |
| `InferToken.t.sol` | Existing deployment, metadata, constructor mint event, CREATE2 factory ownership, transfer and approval events, ERC-20 successes and failures, launch transfer simulation, and inaccessible administrative endpoints. |
| `InferToken.adversarial.t.sol` | One-unit and maximum-integer edges; largest finite allowance; replacing and revoking an infinite allowance; caller identity through a real relay; retry after an insufficient-balance failure; independent owners and spenders; exact transfer round trips. Each fuzz property runs 1,000 cases. |
| `InferToken.invariant.t.sol` | Four actors, ten handler actions, 256 random sequences of depth 128, with unexpected handler reverts treated as failures. |

The invariant checks every actor's balance and all 16 owner/spender allowance
pairs against a model updated only by intended successful actions. It also checks
that balances sum to the fixed supply, metadata remains unchanged, and zero
addresses acquire neither tokens nor allowances. Successful transfers and
approvals are interleaved with overdrafts, revoked grants, invalid recipients,
invalid spenders, and finite/infinite allowance boundaries. Rejected calls must
revert with the expected error and leave the model unchanged; errors after
spending an allowance must restore it. Setup approvals inside a rejection handler
are recorded separately from the rejected spend.

After each random sequence, every holder transfers its entire balance to one
actor and the same invariant is checked again. This exercises empty-account
boundaries and demonstrates that previous failures do not prevent valid transfers.
Both sender/recipient and owner/spender may coincide during random sequences.

The token is deployed directly in these tests. The existing local launch test is
a transfer simulation, not the supplied protected integration with an actual
Uniswap PoolManager. These tests do not certify factory, pool, or distributor code.
