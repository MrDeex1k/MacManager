# Migration and existing-data preservation

Read [project-security-policy.md](project-security-policy.md) first. This reference applies to a specifically requested migration or reset, not routine app startup.

## Establish the contract

Identify the existing item class, service/account or key tag, backend, access group, signing requirements, envelope version, and ciphertext dependents. Read `ClipboardKeychain.swift` and `ClipboardRepository.swift` for the current contract. Verify the destination APIs and entitlements against macOS documentation. A missing preferences flag is not a reinstall or stale-key detector.

## Migration sequence

1. Read and validate the original item without modifying it. Distinguish missing, locked, denied, corrupt, and temporarily unavailable states.
2. Create the destination under its deliberate identity/backend. Handle duplicate creation by reading the existing destination and validating it; do not overwrite an encryption key automatically.
3. Read the destination back, restore/derive its key as appropriate, and verify decryption of representative existing ciphertext.
4. Record completion only after validation. Make interrupted/repeated migration resumable. Keep source data available for the agreed rollback window.
5. Delete only the exact superseded item after the retention policy and authorized migration permit it. Check deletion status. Never enumerate all item classes for a broad wipe.

Changing kSecUseDataProtectionKeychain, kSecAttrService, kSecAttrAccount, access groups, or signing identity can change what is discoverable. Treat those changes as migrations rather than query cleanup.

## Failure and reset behavior

On lock, cancellation, authorization failure, or failed readback/decryption, preserve source material and retry or surface a recoverable error. Do not generate a replacement key merely because an existing key cannot currently be accessed.

For an explicitly requested user reset, explain the loss of access to encrypted history and operate only on MacManager-owned data in the intended storage identity. Shared items require a separate ownership check.

## Verification

Exercise repeat runs, interrupted writes, destination duplicates, locked-session access, preferences reset, decryptability after upgrade, and rollback. Use isolated fixtures and keys; never test deletion against a user's real Keychain. Consult `testing-security-code.md` for mocking and real-system test boundaries.
