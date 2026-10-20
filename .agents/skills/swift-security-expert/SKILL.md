---
name: swift-security-expert
description: Review or implement MacManager Keychain, Secure Enclave, CryptoKit encryption, and sensitive local-data handling. Use for security changes or an explicitly requested security review.
license: MIT
---

# MacManager Security

Read `references/project-security-policy.md` before using any other reference. It defines the macOS storage and migration constraints for this project. Inspect current code and signing/entitlement configuration; the existing design is context to evaluate, not proof that it is secure.

## Workflow

1. Establish scope, protected assets, relevant attacker capability, and the operation being changed. Separate encryption keys, wrapped key envelopes, ciphertext, previews, logs, and preferences.
2. Read only the domain references needed below. Treat imported examples as illustrative and verify platform/version claims against current Apple documentation before relying on them.
3. Trace key creation, persistence, duplicate handling, locked-session behavior, and failure recovery. Classify findings by demonstrated impact rather than a search-pattern match.
4. For authorized fixes, preserve decryptability and existing data. Verify the failure and recovery paths relevant to the change. A review request by itself does not authorize migration or deletion.

## Reference routing

- SecItem queries/errors and backend selection: `references/keychain-fundamentals.md`.
- Protection classes and SecAccessControl: `references/keychain-access-control.md`.
- Hardware-backed key creation/restoration and opaque envelopes: `references/secure-enclave.md`.
- AES-GCM, randomness, and authenticated context: `references/cryptokit-symmetric.md`.
- ECDH/HKDF and key separation: `references/cryptokit-public-key.md`.
- Sensitive storage/logging review: `references/common-anti-patterns.md`.
- Planned storage/backend migration: `references/migration-legacy-stores.md`.
- Mocked and real-system verification: `references/testing-security-code.md`.
- Item-class choice: `references/keychain-item-classes.md`.
- Credential lifecycle: `references/credential-storage-patterns.md`, only when actual credentials are in scope.
- Biometrics: `references/biometric-authentication.md`, only when the feature enforces user authentication; a LocalAuthentication import alone is insufficient.
- Shared access groups or extensions: `references/keychain-sharing.md`, only when implemented or requested.
- Certificate pinning/mTLS: `references/certificate-trust.md`, only when those trust policies are in scope.
- Explicit compliance work: `references/compliance-owasp-mapping.md`; verify identifiers and applicability before claiming compliance.

## Output and verification

For reviews, give file/line evidence, realistic prerequisites, impact, and a scoped correction. Distinguish confirmed defects from open questions and static checks from device validation. For changes, summarize behavior, relevant tests, and remaining runtime checks. Use macOS availability, not default iOS version tags. Findings about networking, input parsing, C code, update authenticity, or signing may require a broader review outside these crypto/storage references.
