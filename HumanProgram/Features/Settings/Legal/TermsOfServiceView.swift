import SwiftUI

// Terms of Service. A thin wrapper over the shared `LegalDocumentView`; the text
// below is kept in sync with the repo-root `TermsOfService.md`.
struct TermsOfServiceView: View {
    enum Mode { case onboarding, reference }
    let mode: Mode
    /// Called when the user confirms in onboarding mode.
    var onConfirm: () -> Void = {}

    var body: some View {
        LegalDocumentView(
            mode: mode == .onboarding ? .onboarding : .reference,
            docTitle: "Terms of Service",
            subtitle: "Effective date: upon your acceptance. Please read these Terms carefully before using the application.",
            sections: Self.sections,
            agreeText: "I have read, understood, and agree to be bound by the Terms of Service.",
            onConfirm: onConfirm
        )
    }

    // MARK: - Content (mirrors TermsOfService.md)

    private static let sections: [LegalSection] = [
        LegalSection(
            title: "Acceptance of These Terms",
            body: "These Terms of Service (the \"Terms\") form a binding legal agreement between you (\"you\" or the \"User\") and David Ko (the \"Developer\") governing your access to and use of the Human Program software application and all related features, content, and updates (the \"App\"). By tapping \"Confirm,\" installing, accessing, or using the App, you acknowledge that you have read, understood, and agree to be bound by these Terms and by any documents incorporated by reference. If you do not agree to these Terms in full, you must not access or use the App, and you should delete it from your device."),
        LegalSection(
            title: "Eligibility",
            body: "You represent that you are at least the age of majority in your jurisdiction, or that you are using the App under the supervision and with the consent of a parent or legal guardian who agrees to be bound by these Terms on your behalf. You further represent that you are not barred from using the App under any applicable law. The App is not directed to children under 13, and the Developer does not knowingly collect information from them; because the App operates on-device and the Developer collects no data (see Section 8), no information is transmitted to the Developer regardless of the User's age."),
        LegalSection(
            title: "License Grant",
            body: "Subject to your continued compliance with these Terms, the Developer grants you a personal, limited, non-exclusive, non-transferable, non-sublicensable, and revocable license to install and use one copy of the App on a device that you own or control, as permitted by the Usage Rules set forth in the Apple Media Services Terms and Conditions, solely for your own personal, non-commercial purposes. All rights not expressly granted to you are reserved by the Developer."),
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
            body: "The App is designed to store your data locally on your device. The App does not transmit your data to the Developer and provides no cloud storage, synchronization, or remote backup. You are solely responsible for backing up your data, including through the App's export feature where available. Backup files are stored unencrypted unless your device or operating system encrypts them. Except for liability that cannot be excluded under applicable law, the Developer is not responsible for, and disclaims any liability arising from, any loss, corruption, deletion, or inaccessibility of your data, whether caused by software defects, device failure, operating-system updates, uninstalling or resetting the App, your own actions, or any other cause."),
        LegalSection(
            title: "Privacy",
            body: "The App is intended to operate on-device and does not include analytics, advertising, or third-party tracking. The App may request permission to access device features (such as your calendar, the ability to send notifications, and Face ID) solely to provide its functionality; you may grant or deny these permissions through your device settings. You are responsible for reviewing the permissions you grant. The Developer's collection and use of information is further described in the Privacy Policy, available within the App, which is incorporated into these Terms by reference."),
        LegalSection(
            title: "Not Professional Advice",
            body: "The App is a personal planning and productivity tool. It does not provide medical, psychological, health, legal, financial, or other professional advice, and nothing in the App should be relied upon as such. The App is not a medical device and is not intended to diagnose, treat, cure, or prevent any condition. You should consult a qualified professional before making decisions that may affect your health, finances, or wellbeing. You are solely responsible for your own decisions and actions."),
        LegalSection(
            title: "Disclaimer of Warranties",
            body: "TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE APP IS PROVIDED \"AS IS\" AND \"AS AVAILABLE,\" WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, THE DEVELOPER DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, INCLUDING BUT NOT LIMITED TO ANY IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE, ACCURACY, AND NON-INFRINGEMENT. THE DEVELOPER DOES NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, TIMELY, SECURE, ERROR-FREE, OR FREE OF DATA LOSS, OR THAT DEFECTS WILL BE CORRECTED. NO ADVICE OR INFORMATION, WHETHER ORAL OR WRITTEN, OBTAINED FROM THE DEVELOPER OR THROUGH THE APP, CREATES ANY WARRANTY NOT EXPRESSLY STATED HEREIN. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF CERTAIN WARRANTIES OR OF IMPLIED TERMS IN CONTRACTS WITH CONSUMERS, SO SOME OR ALL OF THE ABOVE EXCLUSIONS MAY NOT APPLY TO YOU. IN THAT CASE, SUCH WARRANTIES ARE LIMITED TO THE MINIMUM SCOPE AND DURATION PERMITTED BY APPLICABLE LAW."),
        LegalSection(
            title: "Assumption of Risk",
            body: "To the maximum extent permitted by applicable law, you acknowledge and agree that your use of the App is at your own risk, and that you assume responsibility for any consequences arising from that use, including reliance on any reminders, schedules, completion tracking, or other output of the App. The Developer does not guarantee that any reminder or notification will be delivered, delivered on time, or delivered at all."),
        LegalSection(
            title: "Limitation of Liability",
            body: "TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT SHALL THE DEVELOPER BE LIABLE TO YOU OR ANY THIRD PARTY FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, EXEMPLARY, OR PUNITIVE DAMAGES, OR FOR ANY LOSS OF DATA, LOSS OF PROFITS, LOSS OF GOODWILL, BUSINESS INTERRUPTION, OR PERSONAL OR PROPERTY DAMAGE OR HARM, ARISING OUT OF OR RELATING TO THESE TERMS OR YOUR USE OF, OR INABILITY TO USE, THE APP, WHETHER BASED ON WARRANTY, CONTRACT, TORT (INCLUDING NEGLIGENCE), STRICT LIABILITY, OR ANY OTHER LEGAL THEORY, AND WHETHER OR NOT THE DEVELOPER HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. TO THE EXTENT ANY LIABILITY CANNOT BE FULLY DISCLAIMED, THE DEVELOPER'S TOTAL AGGREGATE LIABILITY ARISING OUT OF OR RELATING TO THE APP SHALL NOT EXCEED THE GREATER OF THE TOTAL AMOUNT YOU PAID FOR THE APP, IF ANY, OR ONE U.S. DOLLAR (US $1.00).\n\nNOTHING IN THESE TERMS EXCLUDES OR LIMITS THE DEVELOPER'S LIABILITY FOR: (a) DEATH OR PERSONAL INJURY CAUSED BY THE DEVELOPER'S NEGLIGENCE; (b) FRAUD OR FRAUDULENT MISREPRESENTATION; (c) GROSS NEGLIGENCE OR WILLFUL MISCONDUCT; OR (d) ANY OTHER LIABILITY THAT CANNOT BE EXCLUDED OR LIMITED UNDER APPLICABLE LAW. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OR LIMITATION OF CERTAIN DAMAGES, SO SOME OR ALL OF THE ABOVE MAY NOT APPLY TO YOU; IN SUCH CASES THE DEVELOPER'S LIABILITY IS LIMITED TO THE GREATEST EXTENT PERMITTED BY APPLICABLE LAW."),
        LegalSection(
            title: "Indemnification",
            body: "To the maximum extent permitted by applicable law, you agree to indemnify, defend, and hold harmless the Developer from and against any and all claims, demands, liabilities, damages, losses, costs, and expenses (including reasonable attorneys' fees) arising out of or related to: (a) your use or misuse of the App; (b) your User Content; (c) your violation of these Terms; or (d) your violation of any applicable law or the rights of any third party. This Section does not apply to the extent a claim arises from the Developer's own gross negligence, willful misconduct, or fraud, or where such indemnity is prohibited by applicable consumer law."),
        LegalSection(
            title: "Third-Party Software",
            body: "The App incorporates third-party open-source components, which are licensed under their respective licenses (see Settings → About → Licenses). Those components are provided by their authors \"as is,\" and the Developer makes no warranty regarding them. Your use of those components is subject to their respective license terms."),
        LegalSection(
            title: "Apple-Specific Terms",
            body: "This Section applies to your use of the App obtained through the Apple App Store and supplements the other provisions of these Terms. In the event of any conflict between this Section and the rest of these Terms with respect to App Store distribution, this Section controls.\n\n(a) Acknowledgement. These Terms are concluded between you and the Developer only, and not with Apple Inc. (\"Apple\"). The Developer, not Apple, is solely responsible for the App and its content.\n\n(b) Scope of License. The license granted to you in Section 3 is limited to a non-transferable license to use the App on any Apple-branded products that you own or control, as permitted by the Usage Rules set forth in the Apple Media Services Terms and Conditions, except that the App may be accessed and used by other accounts associated with you via Family Sharing or volume purchasing where applicable.\n\n(c) Maintenance and Support. The Developer is solely responsible for providing any maintenance and support services for the App as required under these Terms or applicable law. Apple has no obligation whatsoever to furnish any maintenance and support services with respect to the App.\n\n(d) Warranty. The Developer is solely responsible for any product warranties, whether express or implied by law, to the extent not effectively disclaimed. In the event of any failure of the App to conform to any applicable warranty, you may notify Apple, and Apple will refund the purchase price (if any) for the App; to the maximum extent permitted by applicable law, Apple will have no other warranty obligation whatsoever with respect to the App, and any other claims, losses, liabilities, damages, costs, or expenses attributable to any failure to conform to any warranty will be the Developer's sole responsibility.\n\n(e) Product Claims. The Developer, not Apple, is responsible for addressing any claims by you or any third party relating to the App or your possession and/or use of the App, including: (i) product liability claims; (ii) any claim that the App fails to conform to any applicable legal or regulatory requirement; and (iii) claims arising under consumer protection, privacy, or similar legislation.\n\n(f) Intellectual Property. In the event of any third-party claim that the App or your possession and use of the App infringes that third party's intellectual property rights, the Developer, not Apple, will be solely responsible for the investigation, defense, settlement, and discharge of any such intellectual property infringement claim.\n\n(g) Legal Compliance. You represent and warrant that you are not located in a country subject to a U.S. Government embargo or designated as a \"terrorist supporting\" country, and that you are not listed on any U.S. Government list of prohibited or restricted parties.\n\n(h) Third-Party Beneficiary. You acknowledge and agree that Apple and Apple's subsidiaries are third-party beneficiaries of these Terms, and that upon your acceptance of these Terms, Apple will have the right (and will be deemed to have accepted the right) to enforce these Terms against you as a third-party beneficiary."),
        LegalSection(
            title: "Updates and Changes to the App",
            body: "The Developer may, but is not obligated to, provide updates, modifications, or new versions of the App, and may add, change, suspend, or discontinue any feature at any time without notice or liability, except as required by applicable law. Continued use of the App after any change constitutes your acceptance of the change."),
        LegalSection(
            title: "Changes to These Terms",
            body: "The Developer may revise these Terms from time to time. The revised Terms will become effective when made available within the App or otherwise published, and, where required, you may be asked to accept them again. Your continued use of the App after the revised Terms take effect constitutes your acceptance of them. If you do not agree to the revised Terms, you must stop using the App."),
        LegalSection(
            title: "Termination",
            body: "These Terms remain in effect until terminated. Your license terminates automatically, without notice, if you breach any provision of these Terms. You may terminate at any time by ceasing all use of the App and deleting it from your device. Upon termination, all rights granted to you under these Terms cease, while the provisions that by their nature should survive (including intellectual property, data-loss disclaimers, warranty disclaimers, assumption of risk, limitation of liability, indemnification, the Apple-specific terms, termination, severability, and governing law) will survive."),
        LegalSection(
            title: "Severability and Waiver",
            body: "If any provision of these Terms is held to be invalid or unenforceable, that provision will be enforced to the maximum extent permissible, and if it cannot be so enforced it will be severed, with the remaining provisions remaining in full force and effect. The Developer's failure to enforce any right or provision of these Terms will not constitute a waiver of that or any other right or provision."),
        LegalSection(
            title: "Governing Law and Dispute Resolution",
            body: "These Terms are governed by and construed in accordance with the laws of the State of California, United States, without regard to its conflict-of-laws principles. You and the Developer agree that the state and federal courts located in California will have exclusive jurisdiction over any dispute arising out of or relating to these Terms or the App, and you consent to personal jurisdiction and venue there. The foregoing does not deprive you of the protection of any mandatory consumer-protection laws of your place of residence; if you are a consumer resident in the European Union, the United Kingdom, or another jurisdiction whose law grants you the right to bring proceedings in your local courts or to rely on mandatory local consumer protections, nothing in this Section removes those rights. The United Nations Convention on Contracts for the International Sale of Goods does not apply to these Terms."),
        LegalSection(
            title: "Contact",
            body: "Questions about these Terms may be directed to the Developer, David Ko, at bluesunshower@gmail.com."),
        LegalSection(
            title: "Entire Agreement",
            body: "These Terms, together with any documents expressly incorporated by reference, constitute the entire agreement between you and the Developer regarding the App and supersede all prior or contemporaneous understandings and agreements, whether written or oral, regarding the same subject matter."),
    ]
}
