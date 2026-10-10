# Vendored dependencies

These are ordinary source files, not submodules. Building and testing requires no
dependency downloads. Upstream files are unmodified and retain their licenses.
`SHA256SUMS` in each dependency directory lists SHA-256 hashes relative to that
directory.

| Dependency | Version | Upstream commit | Included files | License |
| --- | --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0) | v5.1.0 | `69c8def5f222ff96f2b5beff05dfba996368aa79` | ERC20 and its four transitive source dependencies | MIT |
| [Forge Standard Library](https://github.com/foundry-rs/forge-std/tree/v1.9.7) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | Complete `src/` tree; used only by tests | MIT or Apache-2.0 |

Only the OpenZeppelin files are part of the production token's dependency graph.
No upstream build scripts, configurations, or package managers are required.
