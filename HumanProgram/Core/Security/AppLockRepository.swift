import Foundation
import CryptoKit
import Security
import LocalAuthentication

// ── AppLockRepository ──────────────────────────────────────────────────────────
// Owns PIN storage in Keychain and lock settings in UserDefaults.
// All methods are safe to call from the main thread.
public final class AppLockRepository {

    // Keychain identity
    private let keychainService = "app.humanprogram.ios.lock"
    private let keychainAccount = "pin_hash"

    // UserDefaults keys
    private let keyLockEnabled   = "hp.lock.enabled"
    private let keyBiometric     = "hp.lock.biometric"
    private let keyTimeout       = "hp.lock.timeout"

    // ── PIN management ─────────────────────────────────────────────────────────

    /// Hash the PIN with a fresh salt and store "hash:salt" in the Keychain.
    public func setupPIN(_ pin: String) throws {
        let salt = UUID().uuidString
        let hash = sha256(pin + salt)
        let combined = "\(hash):\(salt)"
        guard let data = combined.data(using: .utf8) else {
            throw AppLockError.encodingFailed
        }
        // Remove any existing entry first so SecItemAdd won't fail with errSecDuplicateItem.
        try? keychainDelete()
        try keychainSave(data)
    }

    /// Returns true if the supplied PIN hashes to the stored value.
    public func verifyPIN(_ pin: String) -> Bool {
        guard let data = keychainLoad(),
              let combined = String(data: data, encoding: .utf8) else { return false }
        let parts = combined.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let storedHash = parts[0]
        let salt       = parts[1]
        return sha256(pin + salt) == storedHash
    }

    /// Verify the old PIN then replace with a new one.
    public func changePIN(old: String, new: String) throws {
        guard verifyPIN(old) else { throw AppLockError.incorrectPIN }
        try setupPIN(new)
    }

    /// Delete the PIN from the Keychain and disable the lock.
    public func removePIN() throws {
        try keychainDelete()
        isLockEnabled = false
        isBiometricEnabled = false
    }

    /// Returns true when a PIN entry exists in the Keychain.
    public func hasPIN() -> Bool {
        keychainLoad() != nil
    }

    // ── UserDefaults settings ──────────────────────────────────────────────────

    public var isLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyLockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: keyLockEnabled) }
    }

    public var isBiometricEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: keyBiometric) }
        set { UserDefaults.standard.set(newValue, forKey: keyBiometric) }
    }

    /// Seconds after the app backgrounds before the lock engages. 0 = immediate.
    public var lockTimeoutSeconds: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: keyTimeout)
            // integer(forKey:) returns 0 when the key is absent, which is the correct default.
            return v
        }
        set { UserDefaults.standard.set(newValue, forKey: keyTimeout) }
    }

    // ── Biometrics ─────────────────────────────────────────────────────────────

    public func authenticateWithBiometrics(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }

    // ── Hashing ────────────────────────────────────────────────────────────────

    private func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    // ── Keychain helpers ───────────────────────────────────────────────────────

    private func keychainSave(_ data: Data) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString,
            kSecValueData:   data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AppLockError.keychainError(status)
        }
    }

    private func keychainLoad() -> Data? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrService:      keychainService as CFString,
            kSecAttrAccount:      keychainAccount as CFString,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func keychainDelete() throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: keychainService as CFString,
            kSecAttrAccount: keychainAccount as CFString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppLockError.keychainError(status)
        }
    }
}

// ── Errors ─────────────────────────────────────────────────────────────────────
public enum AppLockError: LocalizedError {
    case encodingFailed
    case incorrectPIN
    case keychainError(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed:        return "Failed to encode PIN data."
        case .incorrectPIN:          return "Incorrect PIN."
        case .keychainError(let s):  return "Keychain error (status \(s))."
        }
    }
}
