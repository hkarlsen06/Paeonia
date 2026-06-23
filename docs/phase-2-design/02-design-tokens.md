# Design Tokens

Tokens are the shared visual language for Paeonia. Feature views should use semantic tokens rather than raw values.

Marketing and native app color direction now follow the delivered logo and app-icon assets. See [Marketing Brand Guidelines](./09-marketing-brand-guidelines.md) for the canonical palette values.

Native app implementation should use a single plum-led brand theme for MVP. Do not build separate light and dark theme palettes unless the product decision is explicitly reopened.

## Color Tokens

Use semantic roles first. Do not scatter raw brand hex values through feature views.

### Background

- `paeoniaBackgroundPrimary`: app root background, based on `paeoniaPlum` (`#380F27`)
- `paeoniaBackgroundSecondary`: deeper grouped/list background, based on `paeoniaPlumDeep` (`#2A0B1E`)
- `paeoniaBackgroundElevated`: sheets, popovers, elevated cards

### Surface

- `paeoniaSurfacePrimary`: main cards, based on `paeoniaPlumRaised` (`#4F203A`) or a materialized variant
- `paeoniaSurfaceSecondary`: secondary cards and grouped rows
- `paeoniaSurfacePressed`: pressed/highlighted surface state
- `paeoniaSurfaceDisabled`: unavailable controls

### Text

- `paeoniaTextPrimary`: primary readable text
- `paeoniaTextSecondary`: supporting text
- `paeoniaTextTertiary`: quiet metadata
- `paeoniaTextInverse`: text on strong accent or dark surfaces

### Accent And State

- `paeoniaAccentPrimary`: primary action/accent, based on `paeoniaPetalLight` (`#F27EB2`)
- `paeoniaAccentSecondary`: stronger pink accent, based on `paeoniaPink` (`#EF5094`)
- `paeoniaSuccess`: success/continued streak/saved
- `paeoniaWarning`: destructive-adjacent or expiring streak warning
- `paeoniaError`: destructive/error
- `paeoniaSyncPending`: pending local changes
- `paeoniaSyncError`: sync problem requiring attention

### Relationship Content

- `paeoniaPartnerOne`: current user/one partner identity accent
- `paeoniaPartnerTwo`: partner identity accent
- `paeoniaMemory`: memory timeline accent
- `paeoniaPrompt`: daily prompt accent
- `paeoniaWidgetDrawing`: widget drawing stroke default

## Spacing Tokens

Use an 8-point-biased scale with a few small exceptions for tight UI.

| Token | Value | Use |
| --- | ---: | --- |
| `space2` | 2 | hairline/tight optical nudges |
| `space4` | 4 | compact icon/text gaps |
| `space8` | 8 | default small gap |
| `space12` | 12 | compact card internals |
| `space16` | 16 | default screen/card padding |
| `space20` | 20 | generous vertical rhythm |
| `space24` | 24 | section spacing |
| `space32` | 32 | major groups |
| `space40` | 40 | hero/top-level rhythm |

Rule: if a feature needs a value outside this scale, explain it in code with a named local constant.

Implementation rule: expose spacing as static constants, not environment values. Spacing should be boring and predictable.

## Corner Radius Tokens

| Token | Value | Use |
| --- | ---: | --- |
| `radius8` | 8 | small controls, chips |
| `radius12` | 12 | fields, small cards |
| `radius16` | 16 | default cards |
| `radius20` | 20 | large cards/sheets |
| `radius28` | 28 | hero surfaces, paywall cards |
| `radiusFull` | full | pills/circular buttons |

Prefer fewer radii per screen. Mixed radii make the app feel unfinished.

Implementation rule: define radii as `CGFloat` constants and use named shape helpers only when they reduce repeated code.

## Stroke Tokens

- `strokeHairline`: 0.5pt for subtle separators
- `strokeDefault`: 1pt for cards and fields
- `strokeEmphasis`: 1.5pt for selected states

Strokes should be semantic, not decorative clutter.

## Shadow And Material Tokens

Use shadows sparingly. Prefer iOS materials when depth is needed.

- `shadowNone`: default
- `shadowSoft`: low-elevation card depth
- `shadowFloating`: sheets/floating controls only
- `materialThin`: low-emphasis translucent surface
- `materialRegular`: modals or widget-adjacent previews

Avoid heavy dark drop shadows. They will fight the intimate tone.

## Layout Tokens

Use shared layout constants for repeated screen structure.

| Token | Value | Use |
| --- | ---: | --- |
| `screenHorizontalPadding` | 20 | default iPhone screen padding |
| `screenTopSpacing` | 24 | top content spacing below navigation |
| `sectionSpacing` | 24 | between major sections |
| `cardContentPadding` | 16 | default card content inset |
| `buttonHeight` | 52 | primary/secondary button height |
| `compactButtonHeight` | 40 | compact controls |

These can evolve, but new values should be deliberate.

## Implementation Rule

When implemented in SwiftUI, tokens should live under:

```text
ios/PaeoniaApp/Shared/DesignSystem/
```

Expected files:

- `PaeoniaColors.swift`
- `PaeoniaSpacing.swift`
- `PaeoniaRadius.swift`
- `PaeoniaTypography.swift`
- `PaeoniaMotion.swift`
- `PaeoniaHaptics.swift`

Do not create parallel light/dark token sets for MVP. `PaeoniaColors.swift` should expose semantic names backed by the canonical plum palette, with accessibility variants only where needed for contrast or system settings.
