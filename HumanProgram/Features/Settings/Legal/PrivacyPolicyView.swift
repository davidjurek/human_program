import SwiftUI

// Privacy Policy. A thin wrapper over the shared `LegalDocumentView`; the text
// below is kept in sync with the repo-root `PrivacyPolicy.md`.
struct PrivacyPolicyView: View {
    enum Mode { case onboarding, reference }
    let mode: Mode
    /// Called when the user confirms in onboarding mode.
    var onConfirm: () -> Void = {}

    /// Hidden access to the acceptance log (reference mode only).
    @State private var showLog = false

    /// The lead paragraph (intro + summary). In the summary sentence the words
    /// "transmit" and "device" are the secret double-tap trigger for the log.
    private static let lead =
        "This Privacy Policy explains how the Human Program application (the \"App\"), developed by David Ko (the \"Developer\"), handles your information. Please read it together with the App's Terms of Service.\n\nThe App does not collect, transmit, sell, or share your personal data. Everything you enter into the App stays on your device. The Developer has no access to your information."

    @ViewBuilder
    var body: some View {
        switch mode {
        case .onboarding:
            LegalDocumentView(
                mode: .onboarding,
                docTitle: "Privacy Policy",
                subtitle: "Last updated: June 15, 2026",
                lead: Self.lead,
                sections: Self.sections,
                agreeText: "I have read, understood, and agree to the Privacy Policy.",
                onConfirm: onConfirm
            )
        case .reference:
            LegalDocumentView(
                mode: .reference,
                docTitle: "Privacy Policy",
                subtitle: "Last updated: June 15, 2026",
                leadView: AnyView(
                    SecretTapParagraph(text: Self.lead, triggers: ["transmit", "device"]) {
                        showLog = true
                    }
                ),
                sections: Self.sections,
                agreeText: ""
            )
            .navigationDestination(isPresented: $showLog) { AcceptanceLogView() }
        }
    }

    // MARK: - Content (mirrors PrivacyPolicy.md)

    private static let sections: [LegalSection] = [
        LegalSection(
            title: "Information We Collect",
            body: "The Developer collects no personal data through the App. The App has no analytics, no advertising, no tracking technologies, and no user accounts. The Developer does not receive, store, or have any access to the content you create or any information about how you use the App."),
        LegalSection(
            title: "Data Stored on Your Device",
            body: "Any data you create in the App — such as tasks, schedules, notes, reminders, and related content (\"Your Data\") — is stored locally on your device only. Your Data is not transmitted to the Developer or to any third party, and the App does not provide cloud storage, synchronization, remote backup, or any other network transmission of Your Data.\n\nBecause Your Data resides on your device, it is subject to your device's own security and storage. You are responsible for securing your device and for creating your own backups. If you delete the App or reset your device, Your Data may be permanently lost."),
        LegalSection(
            title: "Terms and Privacy Acceptance Record",
            body: "Solely as a local confirmation that you agreed to the App's legal terms, the App keeps a record on your device each time you accept the Terms of Service and this Privacy Policy. Each record includes the date and time of acceptance, your device's time zone and region and language settings, basic device information (such as the device model, device name, operating-system version, and the per-installation identifier iOS provides to the App, known as the identifier for vendor), and the App's version. This record is stored only on your device, is never transmitted to the Developer or to any third party, and is used solely to confirm that the agreements were accepted. It is deleted if you delete the App. The App does not record, and the Developer cannot access, hardware serial numbers, your phone number, or your name."),
        LegalSection(
            title: "Device Permissions",
            body: "The App may ask your permission to access certain device features solely to provide its functionality, for example:\n\n• Calendar — to read, add, edit, or delete schedule entries you choose to manage in the App.\n• Notifications — to deliver reminders you set within the App.\n• Face ID / biometrics — to unlock the App if you enable the app lock.\n\nThese permissions are used only on your device to operate the corresponding features. Information accessed through them is not transmitted to the Developer. You may grant or revoke these permissions at any time in your device settings; revoking a permission may disable the related feature."),
        LegalSection(
            title: "No Network Transmission",
            body: "The App is designed to operate entirely on-device and does not send Your Data over the internet to the Developer. The Developer does not operate any server that receives Your Data."),
        LegalSection(
            title: "Third-Party Services",
            body: "The App does not integrate third-party analytics, advertising, or tracking services. The App is distributed through the Apple App Store; your download and any purchase are handled by Apple under Apple's own privacy policy, and the Developer does not receive personal data from Apple beyond aggregate, non-identifying information Apple may make available (such as download counts). The Developer does not control and is not responsible for Apple's privacy practices."),
        LegalSection(
            title: "Children's Privacy",
            body: "The App is not directed to children under 13, and the Developer does not knowingly collect personal information from anyone. Because the App collects no data and transmits nothing to the Developer, no personal information about any user — including children — is received by the Developer."),
        LegalSection(
            title: "Your Rights",
            body: "Because the Developer does not collect or hold any of your personal data, there is no personal data held by the Developer for you to access, correct, delete, or export. You control Your Data directly on your device and may delete it at any time by deleting the relevant content or the App itself.\n\nDepending on where you live, you may have rights under laws such as the California Consumer Privacy Act (CCPA/CPRA) or the EU/UK General Data Protection Regulation (GDPR). These rights generally apply to personal data a business collects or processes. As the Developer collects and processes no personal data through the App, there is no such data to which these rights would attach. This statement does not waive any right you may have under applicable law."),
        LegalSection(
            title: "Changes to This Policy",
            body: "The Developer may update this Privacy Policy from time to time. The updated version will be indicated by a revised \"Last updated\" date and will be effective when made available within the App or otherwise published. Your continued use of the App after an update takes effect constitutes your awareness of the revised policy."),
        LegalSection(
            title: "Contact",
            body: "If you have questions about this Privacy Policy, you may contact the Developer, David Ko, at bluesunshower@gmail.com."),
    ]
}
