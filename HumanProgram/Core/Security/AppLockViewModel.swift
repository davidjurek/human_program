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
    /// Armed when the app locks; the lock screen auto-prompts Face ID once per lock
    /// (so it can't loop on a Face ID cancel, but always engages on each fresh lock).
    public var autoBiometricArmed = false

    public init() {
        // Cold launch: if the lock is enabled, start LOCKED. A terminated app (e.g.
        // swiped away in the app switcher) relaunches fresh, so there's no background/
        // foreground pair to drive the timeout check — without this, a kill+reopen
        // showed the app unlocked. [owner: lock inconsistent after force-quit]
        if repo.isLockEnabled && repo.hasPIN() {
            isLocked = true
            autoBiometricArmed = true
        }
    }

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

    // ── Auth ─────────────────────────────────────────────────────────────────────
    public var isAuthenticating = false

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
            if !isLocked { autoBiometricArmed = true }
            isLocked = true
        }
    }

    /// Auto-engage Face ID if it's enabled and this lock hasn't prompted yet. Called
    /// when the lock screen appears AND when the app becomes active (so a warm return
    /// engages Face ID without the user tapping a button). Disarms after one prompt so
    /// a Face ID cancel doesn't re-loop. [owner: Face ID should auto-engage]
    public func autoPromptBiometricIfArmed() {
        guard isLocked, repo.isBiometricEnabled, autoBiometricArmed, !isAuthenticating else { return }
        autoBiometricArmed = false
        Task { await unlockWithBiometrics() }
    }

    /// Call the moment the app enters the background. Stamps the away-time AND, for a
    /// zero-second ("Lock immediately") timeout, locks right away — so the lock is
    /// already up before the app is shown again (and the app-switcher snapshot is the
    /// lock screen, not your data). This is what makes "Lock immediately" reliable
    /// instead of depending solely on the foreground check firing. [owner: stabilize lock]
    public func handleEnterBackground() {
        lastActiveAt = Date()
        guard repo.isLockEnabled && repo.hasPIN() else { return }
        if repo.lockTimeoutSeconds == 0 {
            if !isLocked { autoBiometricArmed = true }
            isLocked = true
        }
    }

    // ── Unlock via PIN ─────────────────────────────────────────────────────────

    /// Appends a digit to the current PIN input, then auto-submits if it looks
    /// like the user has finished (caller may also call submitUnlockPIN manually).
    public func appendDigit(_ digit: String) {
        guard pinInput.count < maxPINLength else { return }
        pinInput += digit
    }

    public func deleteLastDigit() {
        guard !pinInput.isEmpty else { return }
        pinInput.removeLast()
    }

    /// Attempt to unlock with the current pinInput. Returns true on success.
    /// There is NO lockout / wait-after-N-failures and no reset-after-N — a wrong PIN
    /// just shakes and clears, and the user can retry immediately. [owner: remove lockout]
    @discardableResult
    public func submitUnlockPIN() -> Bool {
        if repo.verifyPIN(pinInput) {
            isLocked = false
            pinInput = ""
            errorMessage = nil
            return true
        }
        // Wrong PIN — shake, clear, allow immediate retry.
        pinInput = ""
        shakeCounter += 1
        errorMessage = "Incorrect PIN"
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
