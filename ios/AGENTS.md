# Paeonia iOS agent guidance

Use SwiftUI, feature-first organization, and the existing MVVM/storage boundaries. Keep business logic outside views. Follow the root product and privacy constraints.

- For architecture, state, persistence, concurrency, or readiness changes, read [iOS architecture](../docs/agent-guides/ios-architecture.md). Loading keys must exclude cosmetic identity updates; preserve stable first presentation and offline content.
- For user-facing copy or catalog edits, read [localization](../docs/agent-guides/ios-localization.md). Use generated String Catalog symbols, English and Norwegian Bokmal, and translator comments.
- For visual or interaction changes, read [design](../docs/agent-guides/ios-design.md). Preserve the single plum theme, semantic tokens, Dynamic Type, Reduce Motion, contrast, VoiceOver, and the established wordmark, banner, and confirmation surfaces.
- For behavior changes, test work, builds, or test execution, read [verification](../docs/agent-guides/ios-verification.md). Use focused checks and the existing repository wrappers; avoid duplicate verification during the user's active Xcode loop.
- For auth, RPC, or backend client changes, read [backend guidance](../backend/AGENTS.md), including the function contracts and explicit authorization checks. The app calls Convex over its HTTP API through `PaeoniaShared/PaeoniaConvexClient.swift` (`POST /api/mutation` and `/api/action`, with the Clerk session token as the bearer). `PaeoniaShared/PaeoniaClerk.swift` configures Clerk for the app and widget. Backend function names and argument names (`p_` prefix) are the contract, so rename them on both sides together.

Paths and commands in the linked guides are relative to the repository root. Read relevant details rather than all guides for every edit.
