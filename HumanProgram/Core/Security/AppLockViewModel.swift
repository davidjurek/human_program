import Foundation
import Observation

// ── AppLockViewModel ───────────────────────────────────────────────────────────
// Drives the lock screen, PIN setup, and all lock/unlock logic.
// Views only call methods on this object — never touch AppLockRepository directly.
@Observable @MainActor
public final class AppLockViewModel {

    public let repo = AppLockRepository()

    // ── Lock state ─────────────────────────────────────────────────────────────
    public var isLocked = false
    public var lastActiveAt = Date()

    // ── PIN entry ──────────────────────────────────────────────────────────────
    /// Digits the user has entered so far on the numpad.
    public var pinInput = ""

    // ── Setup flow ─────────────────────────────────────────────────────────────
    public var setupPhase: PINSetupPhase = .idle
    /// Holds the first PIN entry while waiting for the confirmation step.
    public var firstPINEntry = ""

    // ── Feedback ───────────────────────────────────────────────────────────────
    public var errorMessage: String? = nil
    public var shakeCounter: Int = 0   // increment to trigger shake animation

    // ── Auth / rate limiting ───────────────────────────────────────────────────
    public var isAuthenticating = false
    public var wrongAttempts = 0
    public var lockoutUntil: Date? = nil

    // ── PIN setup phases ───────────────────────────────────────────────────────
    public enum PINSetupPhase: Equatable {
        case idle
        case enterNew
        case confirmNew
        case done
        case error
    }

    // ── Maximum PIN length ─────────────────────────────────────────────────────
    public let maxPINLength = 20
    public let minPINLength = 4

    // ── Lock lifecycle ─────────────────────────────────────────────────────────

    /// Call when the app comes back to the foreground. Locks if enough time has passed.
    public func checkLockOnForeground() {
        guard repo.isLockEnabled && repo.hasPIN() else { return }
        let elapsed = Date().timeIntervalSince(lastActiveAt)
        if elapsed >= Double(repo.lockTimeoutSeconds) {
            isLocked = true
        }
    }

    /// Force the lock screen on immediately (e.g. from Settings "Lock Now" button).
    public func lockNow() {
        guard repo.isLockEnabled && repo.hasPIN() else { return }
        isLocked = true
    }

    /// Call on meaningful user interaction so the timeout clock resets.
    public func recordActivity() {
        lastActiveAt = Date()
    }

    // ── Unlock via PIN ─────────────────────────────────────────────────────────

    /// Appends a digit to the current PIN input, then auto-submits if it looks
    /// like the user has finished (caller may also call submitUnlockPIN manually).
    public func appendDigit(_ digit: String) {
        guard pinInput.count < maxPINLength else { return }
        guard isInLockout == false else { return }
        pinInput += digit
    }

    public func deleteLastDigit() {
        guard !pinInput.isEmpty else { return }
        pinInput.removeLast()
    }

    /// True when the lockout timer is active and the user must wait.
    public var isInLockout: Bool {
        guard let until = lockoutUntil else { return false }
        return Date() < until
    }

    /// Seconds remaining in the current lockout period (0 if not locked out).
    public var lockoutSecondsRemaining: Int {
        guard let until = lockoutUntil, Date() < until else { return 0 }
        return max(0, Int(until.timeIntervalSinceNow.rounded(.up)))
    }

    /// Attempt to unlock with the current pinInput. Returns true on success.
    @discardableResult
    public func submitUnlockPIN() -> Bool {
        // If locked out, reject immediately.
        if isInLockout {
            errorMessage = "Try again in \(lockoutSecondsRemaining)s"
            shakeCounter += 1
            pinInput = ""
            return false
        }

        if repo.verifyPIN(pinInput) {
            isLocked = false
            pinInput = ""
            wrongAttempts = 0
            lockoutUntil = nil
            errorMessage = nil
            return true
        }

        // Wrong PIN
        wrongAttempts += 1
        pinInput = ""
        shakeCounter += 1

        if wrongAttempts >= 10 {
            lockoutUntil = Date().addingTimeInterval(60)
            errorMessage = "Too many attempts. Wait 60 seconds."
        } else if wrongAttempts >= 5 {
            lockoutUntil = Date().addingTimeInterval(30)
            errorMessage = "Too many attempts. Wait 30 seconds."
        } else if wrongAttempts >= 3 {
            lockoutUntil = Date().addingTimeInterval(5)
            errorMessage = "Incorrect PIN. Wait 5 seconds."
        } else {
            errorMessage = "Incorrect PIN"
        }

        return false
    }

    // ── Unlock via biometrics ──────────────────────────────────────────────────

    public func unlockWithBiometrics() async {
        isAuthenticating = true
        let ok = await repo.authenticateWithBiometrics(reason: "Unlock Human Program")
        isAuthenticating = false
        if ok {
            isLocked = false
            pinInput = ""
            wrongAttempts = 0
            lockoutUntil = nil
            errorMessage = nil
        }
    }

    // ── PIN setup flow ─────────────────────────────────────────────────────────

    public func beginSetup() {
        setupPhase = .enterNew
        pinInput = ""
        firstPINEntry = ""
        errorMessage = nil
    }

    /// Called after the user enters their new PIN in the first setup step.
    public func submitFirstPIN() {
        guard pinInput.count >= minPINLength else {
            errorMessage = "PIN must be at least \(minPINLength) digits"
            shakeCounter += 1
            pinInput = ""
            return
        }
        firstPINEntry = pinInput
        pinInput = ""
        errorMessage = nil
        setupPhase = .confirmNew
    }

    /// Called after the user re-enters their PIN in the confirmation step.
    public func submitConfirmPIN() {
        if pinInput == firstPINEntry {
            do {
                try repo.setupPIN(pinInput)
                repo.isLockEnabled = true
                setupPhase = .done
                pinInput = ""
                errorMessage = nil
            } catch {
                setupPhase = .error
                errorMessage = "Could not save PIN. Please try again."
                pinInput = ""
                firstPINEntry = ""
            }
        } else {
            setupPhase = .error
            errorMessage = "PINs did not match. Please start over."
            shakeCounter += 1
            pinInput = ""
            firstPINEntry = ""
        }
    }

    /// Reset setup back to idle (e.g. after a mismatch error or dismissal).
    public func resetSetup() {
        setupPhase = .idle
        pinInput = ""
        firstPINEntry = ""
        errorMessage = nil
    }

    // ── Change PIN ─────────────────────────────────────────────────────────────

    /// Attempt to change the PIN. Returns an error description on failure, nil on success.
    public func changePIN(old: String, new: String) -> String? {
        guard new.count >= minPINLength else {
            return "New PIN must be at least \(minPINLength) digits"
        }
        do {
            try repo.changePIN(old: old, new: new)
            return nil
        } catch AppLockError.incorrectPIN {
            return "Current PIN is incorrect"
        } catch {
            return error.localizedDescription
        }
    }
}
