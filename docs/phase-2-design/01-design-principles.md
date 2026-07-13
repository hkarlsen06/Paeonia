# Design Principles

Paeonia should feel like a private place built for two people. It should not feel like a dating app, social network, productivity tool, or streak game.

## Primary Feeling

The product should feel:

- private
- intimate
- warm
- calm
- premium
- reliable
- emotionally grounded

It can be romantic, but it must not be cheesy. It can be soft, but it must not feel weak or childish.

The locked product feel is **premium calm**. When a design decision could go either more playful/expressive or quieter/premium, choose the calmer premium option unless the feature specifically needs emotional emphasis.

## Product Promise

> A private place for the two of you.

Every surface should support that promise. If a screen does not make the relationship feel clearer, calmer, closer, or more reliable, it should be simplified.

## Design Posture

Use restraint. Paeonia is emotional software, so the UI should leave room for the couple's content to carry the feeling.

Good:

- soft hierarchy
- clear state
- calm motion
- strong empty states
- private, contained surfaces
- warm but concise copy
- tactile native controls

Avoid:

- public-feed aesthetics
- noisy badges
- heavy gamification
- guilt-based streak pressure
- busy floral decoration
- generic dating-app red/pink overload
- excessive gradients without meaning

## Native First

The app should feel deeply iOS-native:

- use SwiftUI idioms where they help
- use Paeonia's single plum-led brand theme instead of separate light and dark appearances
- respect Dynamic Type
- use system gestures and sheet patterns
- prefer platform accessibility over custom behavior
- keep performance and offline responsiveness visible in the feel of the app

Native does not mean bland. It means Paeonia should feel like it belongs on the phone.

## Theme Direction

Paeonia should ship with one canonical app theme for MVP: a plum-led brand surface with pink/petal accents from the logo. Do not design a light mode and dark mode split for native app screens unless that decision is explicitly reopened.

This is a product feeling decision, not just a color preference. The app should feel like a private evening space for two people: calm, warm, and contained. System settings such as Dynamic Type, Reduce Motion, contrast, and accessibility still apply, but the visual identity remains Paeonia's plum theme.

Component styling should be slightly more custom than default iOS controls, but still native in behavior. Customization should show up through spacing, shape, material, haptics, and semantic color, not through alien controls.

## Emotional Hierarchy

The couple's content comes first:

1. partner presence
2. drawings and widget content
3. daily check-in state
4. memories, notes, and photos
5. milestones/countdowns
6. sync and operational status

Operational UI should be clear, but quiet. It should not compete with relationship content.

## Premium Without Being Cold

Premium in Paeonia means:

- consistent spacing
- strong typography
- quiet interactions
- polished empty/loading/error states
- reliable sync and local-first behavior
- App Review-safe subscription presentation

It does not mean corporate, sterile, or luxury-brand cosplay.

## Stable First Frames

The first app surface after launch should only appear once it can render a stable state. If a screen depends on data that changes its first visible layout, offer, eligibility, entitlement, pairing state, or primary action, keep the launch/loading surface visible until that data has loaded or definitively failed.

The launch/loading surface should stay visually blank and copy-free. It is often shown too briefly to read, and readable loading copy creates a distracting flash.

After a stable screen is visible, refreshes should hold the last known stable presentation until the next stable result is ready. Avoid showing intermediate states that briefly change the meaning of the screen, such as a subscription screen flashing from no trial to free trial after StoreKit finishes loading.

When a launch-adjacent screen appears after readiness, prefer a subtle downward settle: content starts slightly above its final position and fades into place. Keep the distance small, skip movement when Reduce Motion is enabled, and avoid upward pushes that can feel like content popping from below.
