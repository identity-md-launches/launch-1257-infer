# Infer (INFER)

`src/InferToken.sol:InferToken` is an immutable ERC-20. Its constructor mints the
entire supply once to `msg.sender`, the immediate deploying address. It uses the
vendored [OpenZeppelin ERC20 v5.1.0 implementation](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.1.0/contracts/token/ERC20/ERC20.sol).

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `InferToken` |
| Token name | `Infer` |
| Token symbol | `INFER` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`) |
| Deployment transaction value | `0` |
| Initial recipient | Immediate creator (`msg.sender`) |
| Initialization calls / linked libraries | None |

## Behavior and assumptions

The requested token is interpreted as a standard transferable ERC-20. There are
no transfer taxes, fees, burns, rebases, vesting, or transfer restrictions beyond
normal balance, allowance, and zero-address validation. No owner, mint endpoint,
pause, blacklist, seizure, upgrade, proxy, permit, or administration is included.
The deployer receives tokens but has no special powers afterward.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert with
ERC-20 custom errors on failure. Transfers and explicit approvals emit the usual
`Transfer` and `Approval` events; the mint emits `Transfer(address(0), deployer,
10^27)`. Zero-value transfers between nonzero addresses are valid. Sending to the
zero address, including zero-value transfers, reverts. Transfers to a contract
do not invoke a recipient callback.

Approvals replace the previous allowance. A finite allowance decreases when used
by `transferFrom`; an allowance of `type(uint256).max` remains unchanged. As in the
vendored ERC-20, spending allowance does not emit a second `Approval` event.
Even a holder calling `transferFrom` on itself needs allowance for a positive
amount; use `transfer` to spend one's own balance directly.

## Build and test

Run at the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, the Cancun EVM target, optimization with 200
runs, and `bytecode_hash = "none"`. All dependency sources and licenses are under
`lib/`; see [dependency provenance](lib/README.md). Nothing needs to be fetched
when the compiler is already installed. FFI and filesystem permissions are not
enabled. Tests use fresh local deployments and deterministic test actors, with
no RPC, environment variables, keys, or time-based waits.

The tests cover metadata, exact constructor allocation and mint event, direct and
CREATE2 factory deployment, exact transfers, zero and self transfers, approvals,
revocation, finite/infinite allowance, allowance isolation, insufficient funds,
zero-address rejection, failed-operation rollback, absence of privileged
endpoints, launch distribution transfers, and runtime opcode/size checks. Five
fuzz tests each run 512 cases. A stateful invariant runs 128 sequences of 64 calls
to compare all tracked balances and allowances against a separate accounting
model and check supply conservation.

The local launch test models the token transfers with a test factory and local
actors; it does not deploy Uniswap or claim to execute a real pool seed or swap.
The supplied protected harness remains the independent launch integration check.

## Deployment and launch responsibilities

The launch network is Ethereum, chain ID `1`. The launch system should deploy
the creation bytecode for `InferToken` directly through its factory with no
constructor arguments and no ETH. The constructor makes no external calls and
works on an empty chain. All `10^27` units initially belong to that factory, not
the transaction origin or the requester. Deploying through another intermediate
contract would give that contract the whole supply instead.

The separate launch system handles the factory, distributor, liquidity, and
manifest. This repository delivers only the token and its local tests. It has no
application contract and deliberately does not create `launch.json`.

The job's launch parameters are recorded here for the operator; they are not
token constructor parameters or token logic:

| Launch setting | Job value |
| --- | --- |
| Paired currency | IMD at `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool fee | `12500` (1.25%) |
| Tick spacing | `60` |
| Pool initial-price provenance value | `79228162514264337593543950336` |
| Pool allocation | `8800` basis points of the whole supply (880,000,000 INFER) |
| Initial market cap | `2500000000000000000000` paired-currency minor units (2,500 IMD) |
| Swarm allocation | Factory forwards 10% (100,000,000 INFER) to the launch distributor |
| Remainder | 2% (20,000,000 INFER) to `0x6bf192ebef135e0f645e99d59d9bf44e7711606c` |

The actual opening price is derived by the launch system from the market cap,
supply, and deployed token address. The token does not reserve or distribute any
of these allocations in its constructor. All holders, including the factory,
distributor, and PoolManager, transfer exact amounts under the same ERC-20 rules.

Before launch, the operator must independently review the token and launch
integration, check the selected bytecode and constructor parameters, and confirm
the factory will distribute its initial balance according to the launch policy.
After deployment, verify the source on the block explorer using the pinned build
settings and confirm the metadata, total supply, mint event, and allocation
transfers. No deployment or broadcast is performed by this project.

## After launch

There are no token settings, owner setters, maintenance jobs, or privileged keys.
Holders are responsible for key custody, choosing correct recipients, and
managing approvals. Prefer approvals limited to the intended spend; replacing a
nonzero allowance has the standard ERC-20 ordering risk, so revoke it first and
confirm the resulting allowance before granting a replacement. The token cannot
recover assets sent to it or an unusable recipient, undo a transfer, freeze an
account, or repair itself through an upgrade.

See [security review notes](SECURITY.md) for the review scope and limitations.
