import SwiftUI
import DSKit

/// Read-only screen listing the third-party open-source libraries the app
/// ships and their licenses. Reached from About → Licenses.
struct LicensesView: View {
    var body: some View {
        SettingsScreen {
            SettingsSectionLabel(title: "Open Source Licenses")

            LicensesIntroText()

            ForEach(thirdPartyLicenses) { license in
                LicenseCardView(license: license)
            }
        }
    }
}

private struct LicensesIntroText: View {
    var body: some View {
        DSText("Human Program is built with the following third-party libraries. Each is included under its respective license. All other code uses Apple frameworks only.")
            .dsTextStyle(.subheadline)
            .padding(.horizontal, 4)
    }
}

private struct LicenseCardView: View {
    let license: ThirdPartyLicense

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DSText(license.name).dsTextStyle(.headline)
            DSText(license.copyright).dsTextStyle(.footnote)
            DSText(license.body).dsTextStyle(.caption1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - License data (file scope keeps the view body simple to type-check)

struct ThirdPartyLicense: Identifiable {
    let id = UUID()
    let name: String
    let copyright: String
    let body: String
}

private let mitLicenseBody = """
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
"""

let thirdPartyLicenses: [ThirdPartyLicense] = [
    ThirdPartyLicense(name: "DSKit",
                      copyright: "Copyright (c) 2023 DSKit (imodeveloper)",
                      body: mitLicenseBody),
    ThirdPartyLicense(name: "SDWebImage",
                      copyright: "Copyright (c) 2009-2023 Olivier Poitrey and contributors",
                      body: mitLicenseBody),
    ThirdPartyLicense(name: "SDWebImageSwiftUI",
                      copyright: "Copyright (c) 2019 SDWebImage and contributors",
                      body: mitLicenseBody)
]
