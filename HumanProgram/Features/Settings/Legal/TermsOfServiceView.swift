import SwiftUI
import DSKit

// Terms of Service. Two presentations share ONE body of legal text:
//  • .onboarding — a full-screen gate shown once on fresh install / after a
//    factory reset. The agree checkbox + Confirm button sit at the very BOTTOM
//    of the scroll, so they're only reachable after scrolling through the terms.
//    Confirm is disabled until the box is checked. The user cannot reach the app
//    without confirming.
//  • .reference — a normal pushed page (Settings → About → Terms of Use), read-only.
//
// NOTE: This is a developer-authored DRAFT to be reviewed by a qualified legal
// professional before release. It is not legal advice.
struct TermsOfServiceView: View {
    enum Mode { case onboarding, reference }
    let mode: Mode
    /// Called when the user confirms in onboarding mode.
    var onConfirm: () -> Void = {}

    @State private var agreed = false
    private let lightBlue = Color(red: 0.42, green: 0.69, blue: 0.99)

    var body: some View {
        switch mode {
        case .reference:
            SettingsScreen(centered: true) { termsText }
        case .onboarding:
            ZStack {
                SettingsBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        termsText
                        gate
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Onboarding gate (bottom of the scroll)

    private var gate: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                .padding(.vertical, 4)

            Button { agreed.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(agreed ? lightBlue : Color.secondary)
                    DSText("I have read, understood, and agree to be bound by the Terms of Service.")
                        .dsTextStyle(.body)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .a11yTapBorder(cornerRadius: 6)

            Button { if agreed { onConfirm() } } label: {
                Text("Confirm").font(appFont(20)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(agreed ? lightBlue : lightBlue.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .a11yTapBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!agreed)
        }
    }

    // MARK: - The terms text (shared by both modes)

    private var termsText: some View {
        VStack(alignment: .leading, spacing: 18) {
            DSText("Terms of Service").dsTextStyle(.title2)
            DSText("Human Program").dsTextStyle(.headline)
            DSText("Effective date: upon your acceptance. Please read these Terms carefully before using the application.")
                .dsTextStyle(.subheadline)

            ForEach(Self.sections.indices, id: \.self) { i in
                section(number: i + 1, Self.sections[i])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func section(number: Int, _ s: LegalSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DSText("\(number). \(s.title)").dsTextStyle(.headline)
            DSText(s.body).dsTextStyle(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct LegalSection { let title: String; let body: String }

    // MARK: - Draft content

    private static let sections: [LegalSection] = [
        LegalSection(
            title: "Acceptance of These Terms",
            body: "These Terms of Service (the \"Terms\") form a binding legal agreement between you (\"you\" or the \"User\") and David Ko (the \"Developer\") governing your access to and use of the Human Program software application and all related features, content, and updates (the \"App\"). By tapping \"Confirm,\" installing, accessing, or using the App, you acknowledge that you have read, understood, and agree to be bound by these Terms and by any documents incorporated by reference. If you do not agree to these Terms in full, you must not access or use the App, and you should delete it from your device."),
        LegalSection(
            title: "Eligibility",
            body: "You represent that you are at least the age of majority in your jurisdiction, or that you are using the App under the supervision and with the consent of a parent or legal guardian who agrees to be bound by these Terms on your behalf. You further represent that you are not barred from using the App under any applicable law."),
        LegalSection(
            title: "License Grant",
            body: "Subject to your continued compliance with these Terms, the Developer grants you a personal, limited, non-exclusive, non-transferable, non-sublicensable, and revocable license to install and use one copy of the App on a device that you own or control, solely for your own personal, non-commercial purposes. All rights not expressly granted to you are reserved by the Developer."),
        LegalSection(
            title: "Intellectual Property and Copyright",
            body: "The App, including its source code, object code, design, user interface, text, graphics, logos, icons, fonts and font configurations, layout, and all other content and materials, and all intellectual property rights therein, are owned by the Developer or the Developer's licensors and are protected by copyright, trademark, and other laws. \"Human Program\" and associated names and marks are the property of the Developer. Nothing in these Terms transfers to you any ownership interest in the App. You must not remove, obscure, or alter any proprietary notices contained in the App."),
        LegalSection(
            title: "Restrictions on Use",
            body: "You agree that you will not, and will not permit any third party to: (a) copy, modify, adapt, translate, or create derivative works of the App; (b) reverse engineer, decompile, disassemble, or otherwise attempt to derive the source code of the App, except to the limited extent such restriction is expressly prohibited by applicable law; (c) rent, lease, lend, sell, sublicense, distribute, or otherwise transfer the App or your rights under these Terms; (d) circumvent, disable, or interfere with any security or access-control feature of the App; (e) use the App to develop a competing product; or (f) use the App in any manner that violates any applicable law, regulation, or third-party right."),
        LegalSection(
            title: "Your Responsibilities",
            body: "You are solely responsible for: (a) the accuracy, legality, and appropriateness of any data, tasks, schedules, notes, images, or other content you create or input into the App (\"User Content\"); (b) maintaining the security of your device, passcode, and any biometric or PIN protection you enable; (c) complying with the terms of any third-party services you connect to the App, including your device calendar and notification systems; and (d) creating and maintaining your own backups of your data. You retain ownership of your User Content; the Developer claims no ownership of it."),
        LegalSection(
            title: "Data Storage, Backups, and Loss of Data",
            body: "The App is designed to store your data locally on your device. The App does not transmit your data to the Developer and provides no cloud storage, synchronization, or remote backup. You are solely responsible for backing up your data, including through the App's export feature where available. Backup files are stored unencrypted unless your device or operating system encrypts them. The Developer is not responsible for, and expressly disclaims any liability arising from, any loss, corruption, deletion, or inaccessibility of your data, whether caused by software defects, device failure, operating-system updates, uninstalling or resetting the App, your own actions, or any other cause."),
        LegalSection(
            title: "Privacy",
            body: "The App is intended to operate on-device and does not include analytics, advertising, or third-party tracking. The App may request permission to access device features (such as your calendar and the ability to send notifications) solely to provide its functionality; you may grant or deny these permissions through your device settings. You are responsible for reviewing the permissions you grant."),
        LegalSection(
            title: "Not Professional Advice",
            body: "The App is a personal planning and productivity tool. It does not provide medical, psychological, health, legal, financial, or other professional advice, and nothing in the App should be relied upon as such. The App is not a medical device and is not intended to diagnose, treat, cure, or prevent any condition. You should consult a qualified professional before making decisions that may affect your health, finances, or wellbeing. You are solely responsible for your own decisions and actions."),
        LegalSection(
            title: "Disclaimer of Warranties",
            body: "THE APP IS PROVIDED \"AS IS\" AND \"AS AVAILABLE,\" WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE DEVELOPER DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, INCLUDING BUT NOT LIMITED TO ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, ACCURACY, AND NON-INFRINGEMENT. THE DEVELOPER DOES NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, TIMELY, SECURE, ERROR-FREE, OR FREE OF DATA LOSS, OR THAT DEFECTS WILL BE CORRECTED. NO ADVICE OR INFORMATION, WHETHER ORAL OR WRITTEN, OBTAINED FROM THE DEVELOPER OR THROUGH THE APP, CREATES ANY WARRANTY NOT EXPRESSLY STATED HEREIN."),
        LegalSection(
            title: "Assumption of Risk",
            body: "You acknowledge and agree that your use of the App is entirely at your own risk, and that you assume full responsibility for any consequences arising from that use, including reliance on any reminders, schedules, completion tracking, or other output of the App. The Developer does not guarantee that any reminder or notification will be delivered, delivered on time, or delivered at all."),
        LegalSection(
            title: "Limitation of Liability",
            body: "TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE DEVELOPER BE LIABLE TO YOU OR ANY THIRD PARTY FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF DATA, LOSS OF PROFITS, LOSS OF GOODWILL, BUSINESS INTERRUPTION, OR PERSONAL OR PROPERTY DAMAGE OR HARM, ARISING OUT OF OR RELATING TO THESE TERMS OR YOUR USE OF, OR INABILITY TO USE, THE APP, WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, OR ANY OTHER LEGAL THEORY, AND WHETHER OR NOT THE DEVELOPER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. TO THE EXTENT ANY LIABILITY CANNOT BE FULLY DISCLAIMED, THE DEVELOPER'S TOTAL AGGREGATE LIABILITY ARISING OUT OF OR RELATING TO THE APP SHALL NOT EXCEED THE GREATER OF THE TOTAL AMOUNT YOU PAID FOR THE APP, IF ANY, OR ONE U.S. DOLLAR (US $1.00). SOME JURISDICTIONS DO NOT ALLOW CERTAIN LIMITATIONS, SO SOME OF THE ABOVE MAY NOT APPLY TO YOU; IN SUCH CASES LIABILITY IS LIMITED TO THE GREATEST EXTENT PERMITTED BY LAW."),
        LegalSection(
            title: "Indemnification",
            body: "You agree to indemnify, defend, and hold harmless the Developer from and against any and all claims, demands, liabilities, damages, losses, costs, and expenses (including reasonable attorneys' fees) arising out of or related to: (a) your use or misuse of the App; (b) your User Content; (c) your violation of these Terms; or (d) your violation of any applicable law or the rights of any third party."),
        LegalSection(
            title: "Third-Party Software",
            body: "The App incorporates third-party open-source components, which are licensed under their respective licenses (see Settings → About → Licenses). Those components are provided by their authors \"as is,\" and the Developer makes no warranty regarding them. Your use of those components is subject to their respective license terms."),
        LegalSection(
            title: "Updates and Changes to the App",
            body: "The Developer may, but is not obligated to, provide updates, modifications, or new versions of the App, and may add, change, suspend, or discontinue any feature at any time without notice or liability. Continued use of the App after any change constitutes your acceptance of the change."),
        LegalSection(
            title: "Changes to These Terms",
            body: "The Developer may revise these Terms from time to time. The revised Terms will become effective when made available within the App or otherwise published, and, where required, you may be asked to accept them again. Your continued use of the App after the revised Terms take effect constitutes your acceptance of them. If you do not agree to the revised Terms, you must stop using the App."),
        LegalSection(
            title: "Termination",
            body: "These Terms remain in effect until terminated. Your license terminates automatically, without notice, if you breach any provision of these Terms. You may terminate at any time by ceasing all use of the App and deleting it from your device. Upon termination, all rights granted to you under these Terms cease, while the provisions that by their nature should survive (including ownership, disclaimers, limitation of liability, and indemnification) will survive."),
        LegalSection(
            title: "Severability and Waiver",
            body: "If any provision of these Terms is held to be invalid or unenforceable, that provision will be enforced to the maximum extent permissible, and the remaining provisions will remain in full force and effect. The Developer's failure to enforce any right or provision of these Terms will not constitute a waiver of that or any other right or provision."),
        LegalSection(
            title: "Governing Law",
            body: "These Terms are governed by and construed in accordance with the laws of the jurisdiction in which the Developer resides, without regard to its conflict-of-laws principles, except where mandatory consumer-protection laws of your place of residence provide otherwise. The specific governing jurisdiction and any dispute-resolution venue will be finalized by the Developer prior to release."),
        LegalSection(
            title: "Entire Agreement",
            body: "These Terms, together with any documents expressly incorporated by reference, constitute the entire agreement between you and the Developer regarding the App and supersede all prior or contemporaneous understandings and agreements, whether written or oral, regarding the same subject matter."),
        LegalSection(
            title: "Contact",
            body: "Questions about these Terms may be directed to the Developer, David Ko, through the contact channel made available for the App."),
    ]
}
