# Motion And Haptics

Paeonia's motion should make the app feel alive without becoming noisy.

The motion direction is premium calm. Haptics should be subtle in ordinary use, but key relationship moments should feel tactile and intentional.

## Motion Principles

Motion should be:

- calm
- fast
- purposeful
- interruptible
- respectful of Reduce Motion

Avoid decorative motion that delays task completion.

## Standard Durations

| Token | Duration | Use |
| --- | ---: | --- |
| `motionFast` | 0.16s | taps, small state changes |
| `motionDefault` | 0.24s | card transitions, reveals |
| `motionSlow` | 0.36s | onboarding/meaningful emotional moments |
| `motionCelebration` | 0.55s max | rare success moments |

Keep most interactions under 0.3 seconds.

## Easing

Use native-feeling spring and ease curves.

Recommended defaults:

- small controls: ease out
- card reveal: soft spring
- sheet transitions: system defaults
- widget drawing feedback: immediate, no lag

## Reduce Motion

If Reduce Motion is enabled:

- no parallax
- no large animated transitions
- no looping decorative movement
- keep opacity/scale changes minimal
- preserve state clarity

## Haptic Events

Use haptics sparingly.

| Event | Haptic |
| --- | --- |
| paired successfully | `UINotificationFeedbackGenerator.FeedbackType.success` |
| answer revealed | `UINotificationFeedbackGenerator.FeedbackType.success` |
| memory saved | `UINotificationFeedbackGenerator.FeedbackType.success` |
| streak continued | `UIImpactFeedbackGenerator.FeedbackStyle.light` |
| drawing sent | `UIImpactFeedbackGenerator.FeedbackStyle.light` |
| partner drawing received while app active | `UIImpactFeedbackGenerator.FeedbackStyle.soft` |
| destructive confirmation shown | no haptic |
| destructive action confirmed | `UINotificationFeedbackGenerator.FeedbackType.warning` |
| validation error | `UINotificationFeedbackGenerator.FeedbackType.error` |

No haptic should fire repeatedly during normal browsing.

Use wrapper APIs in `PaeoniaHaptics` rather than calling feedback generators directly from feature views.

Key moments can use stronger tactile feedback than ordinary controls, especially pairing, shared answer reveal, memory saved, and milestone moments. Avoid using strong haptics for retention pressure or streak anxiety.

## Drawing Interaction

The widget drawing experience is central.

Rules:

- drawing feedback must feel immediate
- do not animate strokes in a way that changes user intent
- sending should feel lightweight
- received drawings may animate in subtly, but must not feel like a social media notification
- continuous stroke input belongs in the app drawing surface; the widget presents the latest shared drawing and can deep-link into drawing or use supported widget controls where appropriate

## Celebration

Celebration is allowed only for moments that matter:

- pairing accepted
- first shared prompt reveal
- first memory created
- anniversary/milestone

Avoid confetti as default. Use softer visual language unless we intentionally choose a more playful direction later.
