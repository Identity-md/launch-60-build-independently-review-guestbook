# Guestbook

Guest (GUEST) is a fixed-supply ERC-20. Guestbook is an append-only public message board: each successful `post(string)` transfers exactly **1 GUEST (10^18 minor units)** from the caller to `0x000000000000000000000000000000000000dEaD`.

## Behavior and assumptions

- Token constructor has no arguments, mints exactly 1,000,000,000 GUEST (10^27 minor units) to its deployer, and emits `Transfer`. Decimals are 18. Supply never changes; payment transfers do not burn supply at the ERC-20 accounting level.
- Guestbook has exactly one nonpayable constructor argument: the deployed Guest address. It rejects zero and addresses without code. Deployment does not transfer tokens or call the token.
- Messages may contain 0–140 **bytes**, including arbitrary bytes. Empty messages and duplicates are allowed. UTF-8 characters can occupy multiple bytes. There is no moderation or erasure; clients must safely escape untrusted content when rendering it.
- First call `Guest.approve(guestbookAddress, amount)`, then `Guestbook.post(message)`. Exact per-post approval limits exposure. The caller is both payer and author; relayers are not supported.
- `post` returns a zero-based ID. `entryCount()` gives the count; `entries(id)` returns `(author, timestamp, message)`. Enumerate IDs from zero to count minus one. Invalid IDs revert. There is no unbounded bulk getter.
- Entries use `block.timestamp` as approximate chain time, not authenticated wall-clock time. Every committed post emits `MessagePosted(id, author, timestamp, message)`.
- All durable token balance and allowance changes emit `Transfer` or `Approval`; unlimited allowances are not decremented. No owner, administrator, mint function, proxy, upgrade path, fee recipient, or withdrawal mechanism exists.
- Entry creation follows checks-effects-interactions and uses a reentrancy guard. A reverted or false-returning payment reverts the entry, event, and guard changes. The guard's transient state is implementation bookkeeping, not a separate user event.
- The application is designed exclusively for this Guest implementation. A malicious token could falsely report payment success; code-length validation does not authenticate a token. Fee-on-transfer, rebasing, and nonstandard no-return tokens are not supported. Release review must verify `$token` resolves to Guest.
- Guestbook does not retain posting payments. Accidental token transfers to the application cannot be recovered. Neither contract accepts ordinary ETH transfers; forcibly sent ETH cannot be recovered. Sending to the conventional dead address is intended to make payments inaccessible; it does not cryptographically prove that no corresponding private key exists.

## Offline development

Requires Foundry and its installed native Solidity **0.8.30** compiler (the execution environment supplies both). Contracts accept Solidity ^0.8.26, and the reproducible project build pins 0.8.30 and Cancun EVM. There are no external Solidity dependencies, package downloads, FFI, filesystem cheatcode permissions, submodules, or deployment scripts.

```sh
forge build --offline
forge test --offline
forge fmt --check
```

Tests use a small local cheatcode interface. Coverage includes supply and metadata, ERC-20 events/permissions/accounting, exact payments, multiple authors, enumeration, immutable history, byte boundaries, multibyte input, missing/revoked/insufficient allowance, insufficient balance, constructor validation, false payments, malicious reentrant callbacks, rollback and recovery, and fuzzed message/accounting cases. Independent reviewer tests also cover factory deployment, runtime size and forbidden opcodes, missing token return data, and allowance exhaustion. The supplied protected files are external verification inputs, not part of this test directory; their exact Solidity 0.8.26 harness and factory environment are run by the admitting verifier, not claimed as locally executed here.

## Sepolia launch and responsibilities

`launch.json` declares kind `evm_project`, the Guest token artifact, and one uniquely named application, Guestbook, with constructor arguments `["$token"]`. No `$owner` or privileged addresses are needed. This is the local launch declaration; the manifest/release operator must validate its schema against the admission tooling and review the finalized manifest and bytecode together before release.

Deployment target is **Sepolia, chain ID 11155111**, through the protocol ProjectFactory. Factory address, policy authorization, salts, predicted addresses, and admitted artifact hashes are supplied and verified by the release operator; none are invented or embedded here. Constructors run with the factory as sender, so Guest mints its entire supply to the factory. Guestbook only stores the Guest address and leaves factory balances unchanged. Subsequent supply allocation/liquidity is the factory's responsibility.

Under the supplied v3 launch terms, the pool has no hook, pairs with native ETH (zero address), uses fee 3000, tick spacing 60, and initial sqrtPriceX96 `79228162514264337593543950336`. The factory seeds token-only liquidity. These are policy pool settings, not a valuation promise or a contributor transaction instruction. The release operator must confirm admitted policy parameters.

The contributor implements, tests, and requests independent review; contributors **never broadcast or access wallet keys**. The independent reviewer examines source, bytecode assumptions, tests, and manifest; see `REVIEW.md`. The admitted release goes through the authorized deployer only after final independent review of the accepted source and finalized manifest. The deployer must verify chain, factory, supply, artifact hashes, constructor arguments, and resolved token address. Any source or manifest change requires renewed review. No deployment has been performed by this project.

Tests and this bounded independent review are not a production security audit. There is no ongoing administrator: operators maintain clients/indexers and monitor events, but cannot modify entries, recover payments, pause posting, or upgrade these deployments.
