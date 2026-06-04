import SwiftUI
import DSKit

// Hidden screen listing every Terms-of-Service + Privacy-Policy acceptance recorded
// on this device (see AcceptanceAuditLog). Reached only by the secret two-word
// double-tap sequence on the Privacy Policy reference screen. A Share button lets
// the whole log be exported off the device as JSON.
struct AcceptanceLogView: View {
    @State private var records: [AcceptanceRecord] = []

    var body: some View {
        SettingsScreen(centered: true) {
            VStack(alignment: .leading, spacing: 20) {
                DSText("Acceptance Log").dsTextStyle(.title2)
                    .frame(maxWidth: .infinity, alignment: .center)

                DSText(records.isEmpty
                       ? "No acceptances recorded yet."
                       : "\(records.count) record\(records.count == 1 ? "" : "s")")
                    .dsTextStyle(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)

                if !records.isEmpty {
                    ShareLink(item: exportText) {
                        DSText("Share / Export").dsTextStyle(.headline, appOnboardingBlue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(appOnboardingBlue.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .a11yTapBorder(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                ForEach(records.indices.reversed(), id: \.self) { i in
                    recordCard(records[i])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { records = AcceptanceAuditLog.allRecords() }
    }

    // One card per record. Newest shown first.
    private func recordCard(_ r: AcceptanceRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            DSText("#\(r.sequence)").dsTextStyle(.headline)
            row("Terms accepted", r.tosAcceptedAt)
            row("Privacy accepted", r.privacyAcceptedAt)
            row("Recorded", r.recordedAt)
            row("Time zone", "\(r.timeZoneIdentifier) (GMT\(offsetString(r.gmtOffsetSeconds)))")
            row("Region", r.regionCode ?? "—")
            row("Language", r.languageCode ?? "—")
            row("Locale", r.localeIdentifier)
            row("Device name", r.deviceName)
            row("Model", "\(r.deviceModel) (\(r.deviceModelIdentifier))")
            row("System", "\(r.systemName) \(r.systemVersion)")
            row("Vendor ID", r.identifierForVendor ?? "—")
            row("App", "\(r.appVersion ?? "—") (\(r.appBuild ?? "—"))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            DSText(label).dsTextStyle(.caption1)
                .frame(width: 120, alignment: .leading)
            DSText(value).dsTextStyle(.caption1, Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func offsetString(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let abs = Swift.abs(seconds)
        return String(format: "%@%02d:%02d", sign, abs / 3600, (abs % 3600) / 60)
    }

    /// Pretty-printed JSON of every record, for the Share sheet.
    private var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }
}
