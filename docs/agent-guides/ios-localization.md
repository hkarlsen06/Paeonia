# Localization

Every user-facing string is localized, in English and Norwegian Bokmal.

### Rules

- Use Xcode String Catalogs and generated `LocalizedStringResource` symbols, such as `Text(.dailyPromptRevealTitle)`. Never pass a raw key to `String(localized:)`, `Text(_:tableName:)`, `LocalizedStringResource(_:table:)` or `NSLocalizedString`. The SwiftLint rule `no_raw_localization_keys` flags it. If a key has no symbol, add or rename the catalog entry so one is generated.
- App Intents metadata is the one exception. The build reads an intent's `title`, its `IntentDescription`, its `@Parameter` titles and an entity's `TypeDisplayRepresentation` from the source text, and it fails on a generated symbol there ("'LocalizedStringResource' must be initialized with a call to its initializer or a string literal"). Write those as `LocalizedStringResource("key", table: "Localizable", comment: "...")`, and keep the key as a manual entry in the catalog. Strings an intent builds while it runs, such as an entity's display title, use generated symbols.
- Use `FormatStyle` for dates, numbers, percentages and countdowns, and the system locale.
- Keep source copy simple enough to translate naturally. Avoid idioms, jokes, technical shorthand and nested clauses.
- Keys use `feature.context.description`, such as `dailyPrompt.reveal.title`.

### Editing string catalogs

For ordinary plain string entries, use the repo helper instead of hand-editing `.xcstrings` JSON:

```bash
./scripts/xcstrings-set ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings pairing.invite.button \
  --comment "Button that starts partner invitation" \
  --en "Invite partner" \
  --nb "Inviter partner"
```

- New keys must include English, Norwegian Bokmal, and a translator comment.
- The helper writes the catalog exactly as Xcode's String Catalog editor saves it, so a later save in Xcode leaves no diff. Edit catalogs with the helper or Xcode, not by hand or with other JSON tools. Another script that writes a catalog should pipe its JSON through `scripts/xcstrings-set --format-stdin`.
- Changing a key's English or Norwegian text marks its other existing translations `needs_review`, except locales passed in the same command, so a later translation pass knows to redo them.
- The helper locks the catalog while it edits, so parallel agents can add keys at the same time. If the edited catalog fails `xcstringstool` validation, it restores the original.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- After catalog changes, `scripts/app-typecheck` shows whether the generated symbols still match.
