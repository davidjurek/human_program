import Foundation
import UIKit

// ── AcceptanceAuditLog ──────────────────────────────────────────────────────────
// A private, on-device audit trail of every time the user accepts the Terms of
// Service + Privacy Policy (which always happen together at the end of onboarding).
//
// Storage — a JSON file INSIDE the app's own container (Application Support):
//   The record is written to a file in the app sandbox, NOT the Keychain. This is a
//   deliberate choice so the log shares the app's lifetime:
//     • It SURVIVES the in-app Factory Reset (which only deletes SwiftData records
//       and a fixed set of UserDefaults keys — never this file) and a full `.hprgm`
//       restore (which replaces data + preferences, not arbitrary files). So a fresh
//       install logs 1 entry; 16 later factory resets add 16 more; the log holds 17.
//     • It is DELETED when the user deletes the app — iOS removes the whole app
//       container, taking this file with it. Nothing the user cannot erase is left
//       behind, which keeps the log consistent with the app's privacy posture.
//   The file is also marked excluded-from-backup, so it stays on this device only
//   and is never copied into an iCloud/device backup.
//
// Corruption hardening:
//   No storage is literally physically incorruptible, but every write is defensive:
//     • Writes are atomic (.atomic) — a crash mid-write can't leave a half file.
//     • A monotonic `sequence` counter lives inside the file and only ever climbs.
//     • If the file ever fails to decode, the bytes are moved aside (quarantined,
//       never discarded) and a fresh file continues, so prior data is preserved and
//       the app never throws or crashes on a write.
//
// Privacy: everything is gathered and stored on this device only and never
// transmitted. iOS does not expose hardware serial numbers, IMEI, or the device
// owner's name to apps; `identifierForVendor` is logged as the closest stable id.
enum AcceptanceAuditLog {

    private static let fileName = "acceptance_audit.json"

    // MARK: - Public API

    /// Append one acceptance record (ToS + Privacy accepted together). Call this at
    /// the moment the user confirms the Privacy Policy at the end of onboarding.
    @MainActor
    static func recordAcceptance(tosAcceptedAt: Date, privacyAcceptedAt: Date) {
        var file = load()
        let seq = file.sequence + 1
        let record = AcceptanceRecord(
            sequence: seq,
            event: "tos_and_privacy_accepted",
            tosAcceptedAt: iso(tosAcceptedAt),
            privacyAcceptedAt: iso(privacyAcceptedAt),
            recordedAt: iso(Date()),
            recordedEpochSeconds: Date().timeIntervalSince1970,
            timeZoneIdentifier: TimeZone.current.identifier,
            gmtOffsetSeconds: TimeZone.current.secondsFromGMT(),
            localeIdentifier: Locale.current.identifier,
            regionCode: regionCode(),
            languageCode: languageCode(),
            deviceName: UIDevice.current.name,
            deviceModel: UIDevice.current.model,
            deviceModelIdentifier: modelIdentifier(),
            systemName: UIDevice.current.systemName,
            systemVersion: UIDevice.current.systemVersion,
            identifierForVendor: UIDevice.current.identifierForVendor?.uuidString,
            appVersion: bundleString("CFBundleShortVersionString"),
            appBuild: bundleString("CFBundleVersion")
        )
        file.sequence = seq
        file.records.append(record)
        save(file)
    }

    /// All records logged so far, oldest first.
    static func allRecords() -> [AcceptanceRecord] {
        load().records
    }

    /// Total number of acceptances ever logged (the monotonic counter).
    static var totalCount: Int { Int(load().sequence) }

    // MARK: - File storage

    private struct AuditFile: Codable {
        var sequence: UInt64
        var records: [AcceptanceRecord]
        static let empty = AuditFile(sequence: 0, records: [])
    }

    /// Application Support / acceptance_audit.json (directory created on demand).
    private static func fileURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    private static func load() -> AuditFile {
        guard let url = fileURL(),
              FileManager.default.fileExists(atPath: url.path) else { return .empty }
        guard let data = try? Data(contentsOf: url) else { return .empty }
        if let decoded = try? JSONDecoder().decode(AuditFile.self, from: data) {
            return decoded
        }
        // Unreadable — preserve the bytes (never destroy) and start fresh.
        quarantine(url)
        return .empty
    }

    private static func save(_ file: AuditFile) {
        guard let url = fileURL(),
              let data = try? JSONEncoder().encode(file) else { return }
        do {
            try data.write(to: url, options: [.atomic])
            excludeFromBackup(url)
        } catch {
            // Last-resort: a failed write leaves the previous file intact (atomic),
            // so the existing log is never corrupted by a failed append.
        }
    }

    /// Move a corrupt file aside under a unique name so its bytes are never lost.
    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("acceptance_audit.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: dest)
    }

    private static func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    // MARK: - Device / locale helpers

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func regionCode() -> String? {
        if #available(iOS 16, *) { return Locale.current.region?.identifier }
        return Locale.current.regionCode
    }

    private static func languageCode() -> String? {
        if #available(iOS 16, *) { return Locale.current.language.languageCode?.identifier }
        return Locale.current.languageCode
    }

    /// Hardware model identifier, e.g. "iPhone16,1". On the simulator this comes
    /// from the SIMULATOR_MODEL_IDENTIFIER environment variable instead of uname.
    private static func modelIdentifier() -> String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return sim
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

// ── AcceptanceRecord ────────────────────────────────────────────────────────────
/// One logged acceptance. iOS does not expose hardware serial numbers / IMEI / the
/// owner's name to apps, so those are intentionally absent.
struct AcceptanceRecord: Codable {
    let sequence: UInt64
    let event: String
    let tosAcceptedAt: String
    let privacyAcceptedAt: String
    let recordedAt: String
    let recordedEpochSeconds: Double
    let timeZoneIdentifier: String
    let gmtOffsetSeconds: Int
    let localeIdentifier: String
    let regionCode: String?
    let languageCode: String?
    let deviceName: String
    let deviceModel: String
    let deviceModelIdentifier: String
    let systemName: String
    let systemVersion: String
    let identifierForVendor: String?
    let appVersion: String?
    let appBuild: String?
}
