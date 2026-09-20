# Independent Guestbook review

Reviewed by a separate contributor agent before any deployment. This is a bounded adversarial code review, not a professional security audit or deployment authorization. No transaction was broadcast.

## Scope and conclusion

Reviewed `src/Guest.sol`, `src/Guestbook.sol`, `test/Guestbook.t.sol`, `foundry.toml`, and `launch.json` against the assignment and the supplied protected token/project checks. No blocking correctness or security defect was identified for the manifest's Guest/Guestbook pairing.

- Guest mints exactly 10^27 minor units to its constructor caller. Its only balance mutation paths are constructor minting and checked transfers. No external mint, administrative, upgrade, arbitrary execution, or supply reduction path exists. Self-transfers and zero-value transfers conserve supply.
- Guestbook binds its sole constructor argument immutably and checks for deployed code. Each accepted message is at most 140 bytes, costs 10^18 minor units, and appends its caller and block timestamp at a stable index. Existing records cannot be edited or deleted.
- Length and reentrancy checks precede effects. The entry and event precede `transferFrom`; false returns and token reverts roll back the entry, payment, allowance effects, and guard together. The guard rejects callbacks before nested writes. The compiler's `reentrancy-no-eth` lint warning concerns the post-call guard reset; the guard is already engaged before the call, so this is not an exploitable callback path.
- Payment goes directly from the author to the specified dead address; the app does not retain payment or levy another fee. Transfer to the dead address does not reduce ERC-20 total supply.
- Foundry disables FFI and filesystem cheatcode access and uses offline compilation with metadata bytecode hashes disabled. The manifest names Guest and Guestbook and supplies exactly `$token` to Guestbook. There is no owner argument or privileged beneficiary. Deployment through a factory leaves the whole initial supply at that factory; application construction does not transfer it.

## Checks performed

`forge build --offline` succeeded, and all 15 delivered tests passed, including 256 runs of each of two fuzz tests. Independently authored tests in `test/IndependentReview.t.sol` also passed (3 tests): factory deployment and supply preservation; runtime size and forbidden-opcode scan for both contracts; missing token return-data rollback; and exhausted finite allowance with payment conservation. These independent checks are included as delivered regression tests.

The protected suites were read, not run verbatim: their execution requires the verifier's deployment environment and `forge-std`. The independent runtime/factory tests reproduce relevant baseline assertions without claiming to replace those trusted checks.

## Assumptions and release responsibilities

1. The deployer must bind Guestbook to the reviewed Guest artifact through `$token` and verify the admitted source, compiler settings, manifest, bytecode, Sepolia chain, and factory. A code-length check cannot prove ERC-20 honesty: a substituted token can return true without payment or charge transfer fees. The supplied Guest has neither behavior. No-return ERC-20 variants are intentionally unsupported and fail atomically.
2. Messages, including empty strings and arbitrary non-UTF-8 byte sequences, are public and permanent. The length restriction counts bytes. There is no moderation, deletion, pause, refund, or recovery authority. Timestamps are block timestamps rather than precise civil-time attestations.
3. Transferring to the dead address is treated as economically irreversible under the usual assumption that nobody controls that address. The app provides no rescue path for unsolicited token transfers or forcibly sent ETH.
4. This review covers the currently reviewed local source and manifest. Any later manifest or source change must be reviewed again before release. Final factory/policy integration and deployment remain the admitted release deployer's responsibilities; contributors must not broadcast.
