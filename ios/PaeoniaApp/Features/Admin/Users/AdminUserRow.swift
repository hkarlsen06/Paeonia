import SwiftUI

/// A user in a list: name, how they sign in, and a tag for banned users and admins.
struct AdminUserRow: View {
    let name: String?
    let provider: AuthProvider
    let isAdmin: Bool
    let isBanned: Bool

    init(user: AdminUserSummary) {
        name = user.displayName
        provider = user.authProvider
        isAdmin = user.isAdmin
        isBanned = user.isBanned
    }

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space12) {
            VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
                AdminUserName(name: name)
                    .font(PaeoniaTypography.bodyEmphasis)
                    .foregroundStyle(.paeoniaTextPrimary)

                Text(provider.adminTitle)
                    .font(PaeoniaTypography.caption)
                    .foregroundStyle(.paeoniaTextSecondary)
            }

            Spacer(minLength: PaeoniaSpacing.space8)

            AdminUserTags(isAdmin: isAdmin, isBanned: isBanned)
        }
        .padding(.vertical, PaeoniaSpacing.space4)
        .accessibilityElement(children: .combine)
    }
}

/// A name, or "No name" for someone who has not set one.
struct AdminUserName: View {
    let name: String?

    var body: some View {
        if let name = name?.trimmedNonEmpty {
            Text(name)
        } else {
            Text(.adminUserNoName)
        }
    }
}

/// The "Banned" and "Admin" tags. Banned is the one that can mean trouble, so it is red.
struct AdminUserTags: View {
    let isAdmin: Bool
    let isBanned: Bool

    var body: some View {
        HStack(spacing: PaeoniaSpacing.space4) {
            if isAdmin {
                tag(.adminTagAdmin, color: .paeoniaAccentPrimary)
            }
            if isBanned {
                tag(.adminTagBanned, color: .paeoniaErrorText)
            }
        }
    }

    private func tag(_ title: LocalizedStringResource, color: Color) -> some View {
        Text(title)
            .font(PaeoniaTypography.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, PaeoniaSpacing.space8)
            .padding(.vertical, PaeoniaSpacing.space2)
            .background(color.opacity(0.16), in: Capsule())
    }
}

extension AuthProvider {
    var adminTitle: LocalizedStringResource {
        switch self {
        case .apple: .adminProviderApple
        case .google: .adminProviderGoogle
        case .development, .unknown: .adminProviderUnknown
        }
    }
}

extension AdminUserDetail {
    /// The name for titles and sentences.
    var nameForMessages: String {
        displayName?.trimmedNonEmpty ?? String(localized: .adminUserNoName)
    }
}
