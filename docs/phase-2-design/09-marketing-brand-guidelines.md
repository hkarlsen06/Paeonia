# Marketing Brand Guidelines

These guidelines are for updating Paeonia's public marketing page after the new logo and brand colors have landed. They use the existing Phase 2 design foundation as the product baseline, but they are specific to the marketing site.

The goal is a page another agent can implement without guessing core visual or copy decisions.

## Creative North Star

**A quiet private room for two people who are apart.**

Paeonia should feel romantic, private, premium, calm, and resilient. It should make long distance feel held and intentional, not dramatic or needy. The brand can be soft, but it must not become childish. It can be romantic, but it must not use generic dating-app red, heart-heavy decoration, or guilt.

The marketing page should communicate:

- This is a private app for one couple.
- Distance can feel lighter when there is a shared place to return to.
- The product is warm and emotional, but trustworthy.
- The interface is simple enough to understand quickly.
- The relationship content is the focus, not the software.

## Physical Scene

Assume someone opens the page on a phone in the evening, maybe after a call or while missing their partner. The ambient mood is quiet, dim, and personal. This supports a **plum-led dark brand surface** with warm blush text and pink accents. Use light blush sections as breathing space, not as the default page identity.

## Brand Strategy

Use a **Committed / Drenched** color strategy for the hero and top-level brand moments. Plum should carry the page. Pink should feel like connection and presence, not decoration.

Do not reduce Paeonia to a beige romance landing page. Do not copy Tidex's blue, ledger-like confidence. Use Tidex as a quality baseline for structure, semantic tokens, clear component rules, and maintainable CSS organization only.

## Brand Assets

Canonical asset sources:

- `design/brand/web/58860_Paeonia_RM-01.svg`: full lockup with symbol, wordmark, and tagline.
- `design/brand/web/58860_Paeonia_RM-02.svg`: compact app-icon mark with plum rounded square.
- `design/app-icon/source/concepts/paeonia-app-icon-mark.svg`: app-icon source copy of RM-02.
- PNG and JPG exports are previews or fallbacks. Source vectors are canonical.

### Logo Usage

Use the full lockup when the wordmark and tagline are legible:

- launch hero
- footer brand block
- Open Graph image
- press or app-store-adjacent brand panels

Use the compact mark when space is tight:

- favicon and app icons
- mobile header
- small CTA blocks
- social preview crops

Rules:

- Keep clear space around the logo at least equal to the height of one petal shape.
- Do not stretch, rotate, outline, or add drop shadows to the SVG logo.
- Do not recolor individual petals unless a full brand refresh explicitly approves it.
- Do not place the pink wordmark on a busy or low-contrast image.
- Do not use the full lockup below roughly 180px wide if the tagline remains visible. Use the mark or a text label instead.
- Prefer the original plum background for brand moments. On light blush backgrounds, use the mark with enough surrounding white or blush space.

### Mark Meaning

Treat the abstract two-part peony mark as both flower and connection. It should suggest two people reaching toward each other without becoming literal hands, hearts, or chat bubbles.

## Color System

The delivered SVG colors are the brand anchor:

| Token | Hex | OKLCH | Use |
| --- | --- | --- | --- |
| `paeoniaPlum` | `#380F27` | `oklch(24.6% 0.072 347.5)` | Main hero background, nav, footer, deep panels |
| `paeoniaPlumDeep` | `#2A0B1E` | `oklch(21.0% 0.058 345.5)` | Deeper background, vignette, bottom mobile CTA |
| `paeoniaPlumRaised` | `#4F203A` | `oklch(32.1% 0.079 348.1)` | Raised dark panels, subtle borders, hover states |
| `paeoniaPink` | `#EF5094` | `oklch(66.7% 0.203 357.9)` | Primary brand accent from logo |
| `paeoniaPetalLight` | `#F27EB2` | `oklch(73.8% 0.153 353.3)` | Soft accent, glow, mark-adjacent details |
| `paeoniaPetalWarm` | `#E85D86` | `oklch(66.7% 0.175 4.8)` | Secondary petal accent, hover, illustration depth |
| `paeoniaBlush` | `#FBF3F7` | `oklch(97.1% 0.010 345.4)` | Light section background |
| `paeoniaBlushSurface` | `#FFF9FC` | `oklch(98.8% 0.007 345.3)` | Cards on light sections, never pure white |
| `paeoniaPetalMist` | `#FDE7F1` | `oklch(94.8% 0.027 348.3)` | Accent wash, dividers, quiet badges |
| `paeoniaTextMuted` | `#7A5369` | `oklch(49.2% 0.061 344.7)` | Secondary text on light surfaces |
| `paeoniaBerry` | `#A83370` | `oklch(51.3% 0.163 352.3)` | Accessible pink text/link on light surfaces |

### Color Rules

- Use plum as the primary brand color. It should own the hero and footer.
- Use pinks from the logo as accents. They should not cover every section.
- Never use pure `#000` or `#fff`. Use plum-tinted darks and blush-tinted lights.
- Avoid generic red. Error/destructive states can use a muted rose or system red only when the state is real.
- Avoid rainbow romance palettes. Paeonia is not a candy or dating-card brand.
- Gradients may be used as ambient light, such as plum to deep plum or a soft pink radial glow. Do not use gradient text.

### Contrast Rules

Known safe combinations:

- `#FBF3F7` on `#380F27`: 15.22:1.
- `#FFF9FC` on `#380F27`: 15.96:1.
- `#F27EB2` on `#380F27`: 6.64:1.
- `#EF5094` on `#380F27`: 4.93:1.
- `#380F27` on `#FFF9FC`: 15.96:1.
- `#A83370` on `#FFF9FC`: 5.99:1.
- `#7A5369` on `#FFF9FC`: 6.18:1.

Unsafe for normal text:

- `#EF5094` on `#FFF9FC`: 3.24:1.
- `#E85D86` on `#FFF9FC`: 3.19:1.

Use bright pink on light backgrounds only for large decorative marks, icons with labels, or non-text accents. For links on light backgrounds, use `paeoniaBerry`.

## Typography

Use Apple/system typography for MVP, consistent with the existing typography decision.

Recommended stack:

```css
font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
```

The logo wordmark is the brand display voice. Do not add a separate decorative romance font for headings.

### Marketing Type Scale

| Role | Suggested CSS | Use |
| --- | --- | --- |
| Hero | `clamp(3.25rem, 9vw, 7.5rem)`, `line-height: 0.92-1.0`, `font-weight: 650-750`, `letter-spacing: -0.07em` | One emotional promise |
| Section heading | `clamp(2rem, 5vw, 4.25rem)`, `line-height: 1.02`, `font-weight: 650`, `letter-spacing: -0.05em` | Major story beats |
| Subheading | `1.125rem-1.375rem`, `line-height: 1.55-1.75` | Explain the promise |
| Body | `1rem`, `line-height: 1.65-1.8` | Readable content |
| Label | `0.8125rem-0.875rem`, `font-weight: 650`, slight negative or neutral tracking | Short labels, not repeated above every section |
| Button | `0.9375rem-1rem`, `font-weight: 650` | CTAs |

Rules:

- Body copy should stay around 55 to 70 characters per line.
- Use weight, size, and spacing for hierarchy. Do not rely on pink text everywhere.
- Avoid all-caps body copy. The logo tagline can stay as delivered.
- Do not use monospace as a brand motif.

## Layout And Spacing

Marketing should feel spacious and intimate, not empty. Use a strong mobile-first rhythm because the product is phone-native.

### Page Structure

Recommended landing page order:

1. Hero with full brand mood, concise promise, primary CTA, and app/widget preview.
2. Private place section explaining that Paeonia is for one couple.
3. Long-distance section showing what the product helps with: drawings, check-ins, memories, milestones.
4. Product preview section with iPhone and widget visuals.
5. Privacy/trust section in plain language.
6. Subscription/value section if needed, including that one paying partner unlocks both.
7. FAQ and support.
8. Footer with logo, legal links, and support.

### Spacing Rhythm

Use the existing product spacing scale as the base, then allow larger marketing steps:

| Token | Suggested value | Use |
| --- | ---: | --- |
| `marketingSpaceXS` | 8px | Icon/text gaps |
| `marketingSpaceS` | 16px | Button groups, compact copy |
| `marketingSpaceM` | 24px | Card and panel padding |
| `marketingSpaceL` | 40px | Hero copy groups, section intro spacing |
| `marketingSpaceXL` | 64px | Section internal rhythm |
| `marketingSpaceXXL` | 96px | Between major story sections |
| `marketingSpaceHuge` | `clamp(6rem, 14vw, 12rem)` | Full-page pacing |

Rules:

- Do not center every section. Use left-aligned copy with asymmetry in at least the hero and one product-preview section.
- Avoid identical card grids. If features need grouping, vary scale or presentation.
- Avoid nested cards. Use one panel, then rows, dividers, or soft tonal bands inside it.
- Use rounded corners intentionally: 16px for small panels, 24px for cards, 32px or more for hero devices and large surfaces.

## Component Guidance

### Header

Use the compact mark plus Paeonia text or the full lockup if space allows. Keep the header quiet:

- no heavy nav
- no many links before launch
- one primary CTA at most
- language switcher can be small and calm

### Buttons

Primary CTA:

- plum page: blush or petal-light filled button with plum text
- light page: plum filled button with blush text
- height 48 to 56px
- pill or large rounded rectangle
- visible focus ring using `paeoniaPetalLight` or `paeoniaBerry`

Secondary CTA:

- transparent or soft petal mist
- clear border or underline
- never lower contrast than body text

Button copy should be direct:

- "Join the waitlist"
- "Get Paeonia"
- "Read about privacy"
- "Contact support"

Avoid:

- "Start your love story"
- "Make them miss you"
- "Never lose the spark"

### Panels

Use panels for privacy, subscription, or FAQ content. Panels should feel like private notes, not SaaS cards:

- soft blush surfaces on light sections
- plum-raised surfaces on dark sections
- subtle border, no heavy shadow
- no colored side-stripe borders
- no decorative glass cards

### Product Preview

The strongest marketing visual should be the app or widget, not abstract cards.

Use:

- iPhone preview with a calm plum/blush app screen
- widget preview showing a shared drawing or quiet partner presence
- the app icon mark as a small brand object

Do not build a fake analytics dashboard or a generic chat-app mockup.

### FAQ

Use an accordion or simple stacked questions. Questions should be human:

- "Is Paeonia private?"
- "Do both people need to pay?"
- "What happens if we are offline?"
- "Can we use it from different countries?"

Answers should be short and plain.

## Imagery And Illustration

Paeonia should use product-led imagery first.

Preferred imagery:

- app screenshots
- widget screenshots
- close crops of the app icon mark
- abstract petal or connection shapes derived from the SVG
- soft drawn lines that feel like private notes or shared sketches

Use photography sparingly. If used, avoid stock photos of couples staring at sunsets, engagement-style hands, roses, hearts, or staged video-call sadness. The brand should not feel like an ad for dating or wedding services.

Illustration rules:

- Use the two-part petal logic from the mark as the shape language.
- Keep lines soft and intentional.
- Avoid literal flowers as wallpaper.
- Avoid hearts, cupid imagery, locks as privacy shorthand, and cartoon mascots.
- Let whitespace and color create romance before adding decoration.

## Motion

Motion should feel like a quiet reveal.

Use:

- one page-load sequence in the hero
- subtle fade and upward movement of 6 to 10px
- slow ambient glow changes only if they do not distract
- phone/widget preview entrance after text, not before it
- accordion motion that is quick and calm

Timing:

- small UI transitions: 160 to 220ms
- section reveals: 320 to 520ms
- hero first-load sequence: up to 700ms total

Easing:

- use ease-out quart, quint, or expo
- do not use bounce or elastic motion
- do not animate layout-heavy properties
- respect `prefers-reduced-motion`

No confetti, pulsing hearts, floating emojis, or urgent streak motion.

## Copy Voice

The marketing voice should be understandable to an ordinary 16-year-old. It should feel warm, direct, private, and trustworthy.

Voice:

- romantic without being cheesy
- calm without being cold
- premium without sounding luxury-corporate
- clear about privacy
- honest about paid features and availability

Avoid:

- guilt
- jealousy
- possessiveness
- fake urgency
- dating-market language
- technical implementation wording
- overpromising emotional outcomes

Preferred terms:

- partner
- the two of you
- private place
- shared space
- drawing
- check-in
- memory
- milestone
- invite

Avoid:

- match
- follower
- audience
- feed
- engagement
- viral
- soulmate claims
- surveillance language

### Sample Copy Direction

Good hero lines:

- "A private place for the two of you."
- "Feel close, even when the days happen apart."
- "Small notes, shared moments, and quiet reminders for long-distance couples."

Good privacy lines:

- "Paeonia is built for one relationship, not a feed."
- "Your shared space stays between you and your partner."
- "Invite your partner, then build the space together."

Avoid:

- "The ultimate app for lovers."
- "Never let distance win."
- "Keep your partner hooked."
- "AI-powered relationship engagement."

## Accessibility

Marketing accessibility is part of the brand. Privacy and romance do not excuse low contrast or vague controls.

Rules:

- Meet WCAG AA contrast for all normal text.
- Keep primary CTAs at least 44px tall, preferably 48px or taller.
- Use visible focus states on buttons, links, accordions, and language controls.
- Do not communicate state with color alone.
- Provide alt text for logo and product imagery.
- Decorative petals and glows should be `aria-hidden`.
- Respect `prefers-reduced-motion`.
- Keep legal, privacy, and subscription copy readable without tiny text.

Alt text examples:

- Full lockup: "Paeonia, a private place for the two of you."
- App icon: "Paeonia app icon."
- Product preview: "Paeonia app showing a private shared space for a couple."

## Implementation Notes For The Marketing Agent

When updating `marketing/`:

- Prefer semantic CSS custom properties or Tailwind theme tokens for the palette.
- Keep the public page structure simple. Do not add a design-system package unless the page grows enough to need it.
- Use SVG assets from `design/brand/web/` or copied public equivalents. Do not trace or recreate the logo.
- Keep locale dictionaries in sync for English and Norwegian.
- Use the current marketing app structure as the implementation target: `marketing/components/LandingPage.tsx`, `marketing/components/SiteShell.tsx`, `marketing/app/globals.css`, and `marketing/lib/i18n/dictionaries/`.
- If adding app screenshots, prefer real product captures. If those are not ready, use clearly intentional product mockups, not blank panels.

## Do And Do Not

Do:

- Lead with plum.
- Use pink as connection and warmth.
- Keep copy short and human.
- Show the product or widget.
- Make privacy visible.
- Use the logo assets exactly.
- Preserve a premium calm mood.

Do not:

- Make the page red, loud, or gamified.
- Use hearts, streak pressure, or jealousy.
- Use gradient text.
- Use colored side-stripe cards.
- Use glassmorphism as a default style.
- Build identical icon-card grids.
- Turn the page into a technical feature list.
- Make Paeonia feel like a generic dating app.

## Open Decisions

Recommended defaults are listed here so implementation can proceed, but these still deserve owner approval:

| Decision | Recommendation |
| --- | --- |
| Primary marketing CTA before launch | Use "Join the waitlist" if collection exists. Otherwise use "Get notified" or keep "Contact support" only. |
| App Store timing | If the app is not live, do not show an App Store badge. Use a waitlist or launch notice instead. |
| Product screenshots | Use real app/widget screenshots once available. Until then, use carefully labeled mockups based on actual planned UI. |
| Full lockup in header | Use the compact mark on mobile. Use full lockup only where the tagline remains legible. |
| Light sections | Use blush sections for privacy, FAQ, and legal-adjacent content. Keep hero and footer plum-led. |
| Photography | Avoid for the first pass unless there is a specific, approved image direction. Product and brand assets are stronger. |
