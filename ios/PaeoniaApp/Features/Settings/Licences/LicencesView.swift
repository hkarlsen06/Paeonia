import SwiftUI

/// The open source software Paeonia uses. Each licence asks that its text comes
/// with the app, so every package opens its full licence.
struct LicencesView: View {
    @State private var packages: [PackageLicence] = []

    var body: some View {
        List {
            Section {
                ForEach(packages) { package in
                    NavigationLink {
                        PackageLicenceView(package: package)
                    } label: {
                        Text(verbatim: package.name)
                            .foregroundStyle(.paeoniaTextPrimary)
                    }
                    .accessibilityIdentifier("licences.package")
                }
            } header: {
                Text(.settingsLicencesIntro)
                    .textCase(nil)
            }
            .listRowBackground(Color.paeoniaSurfacePrimary)
        }
        .paeoniaGroupedList()
        .navigationTitle(Text(.settingsLicencesTitle))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if packages.isEmpty {
                packages = PackageLicence.bundled()
            }
        }
    }
}

/// One package's licence in full. Licences are legal texts in English, so they
/// are shown as written.
private struct PackageLicenceView: View {
    let package: PackageLicence

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space16) {
                Text(verbatim: package.source)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)

                Text(verbatim: package.text)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextPrimary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("licences.text")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
            .padding(.top, PaeoniaSpacing.screenTopSpacing)
            .padding(.bottom, PaeoniaSpacing.space40)
            .paeoniaReadableWidth(alignment: .leading)
        }
        .paeoniaScreenBackground()
        .navigationTitle(Text(verbatim: package.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
