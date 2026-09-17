# Localization

Localization is required for all user-facing strings.

Start with English and Norwegian Bokmal. The setup must make later languages straightforward.

### Rules

- Use Xcode String Catalogs.
- Use generated `LocalizedStringResource` symbols in Swift code.
- Do not use raw string keys in localization calls.
- Avoid patterns such as:
  - `String(localized: "settings.saveButton")`
  - `Text("settings.saveButton", tableName: "Localizable")`
  - `LocalizedStringResource("settings.saveButton", table: "Localizable")`
  - `NSLocalizedString("settings.saveButton", ...)`
- If a key has no generated symbol, add or rename the catalog entry so a symbol is generated.
- Prefer `FormatStyle` for dates, numbers, percentages, and countdowns.
- Use the system locale. Do not override locale globally unless there is a specific product requirement.
- Keep source copy simple enough to translate naturally. Avoid idioms, jokes, technical shorthand, and nested clauses.

### Key Naming

Use dot-notation keys:

```text
feature.context.description
```

Examples:

```text
dailyPrompt.reveal.title
pairing.invite.button
countdown.daysRemaining
settings.notifications.title
```

Generated symbols should be used like:

```swift
Text(.dailyPromptRevealTitle)
String(localized: .countdownDaysRemaining(Int32(days)))
```

### Editing String Catalogs

For ordinary plain string entries, use the repo helper instead of hand-editing `.xcstrings` JSON:

```bash
./scripts/xcstrings-set ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings pairing.invite.button \
  --comment "Button that starts partner invitation" \
  --en "Invite partner" \
  --nb "Inviter partner"
```

- New keys must include English, Norwegian Bokmal, and a translator comment.
- The helper preserves existing catalog order by default to keep diffs focused. Pass `--sort-keys` only when intentionally normalizing a catalog.
- Use `--locale <code>=<value>` for additional languages if the catalog grows beyond `en` and `nb`.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- After catalog changes, verify generated symbols in Swift code still match the key names. Use the repository build wrapper when generated-symbol correctness needs verification; avoid duplicating a build the user is already running.
