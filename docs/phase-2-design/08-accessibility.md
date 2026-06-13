# Accessibility

Accessibility is part of the design foundation. Paeonia handles private emotional content, so the app must be clear and comfortable for people using different input, vision, hearing, and motion settings.

## Baseline Requirements

- Support Dynamic Type on all core screens.
- Support VoiceOver labels for all controls and relationship-state content.
- Support Reduce Motion.
- Do not rely on color alone to communicate state.
- Keep tap targets at least 44x44pt.
- Maintain sufficient contrast in light, dark, and tinted contexts.
- Provide text alternatives for icon-only controls.

## VoiceOver

Important elements need explicit labels:

- invite code controls
- relationship state
- check-in status
- memory media actions
- voice note controls
- drawing controls
- widget status where possible
- destructive actions

Avoid exposing decorative layout details to VoiceOver.

## Color And Contrast

Final colors are deferred, but contrast rules are not.

When the palette is chosen:

- primary text must pass contrast on primary backgrounds
- secondary text must remain readable, not merely aesthetic
- accent buttons must support readable text
- error/warning/success states need non-color affordances where needed

## Motion Sensitivity

If Reduce Motion is enabled:

- skip decorative animation
- avoid parallax
- avoid large scale transitions
- keep state changes clear with simple opacity or instant transitions

## Hearing

Voice notes are a V1 feature, so the UI should not assume audio is always available.

MVP requirements:

- voice notes need clear playback controls
- playback state must be visible, not audio-only
- duration should be visible
- failed playback/upload states must be textual

Transcription is not part of MVP unless explicitly added later.

## Drawing Accessibility

Drawing is expressive, but not every user can draw precisely.

The drawing experience should support:

- undo
- clear with confirmation when destructive
- simple stroke size/color controls
- large enough drawing controls
- clear sent/synced state

Do not make drawing the only way to communicate a required action.

## Testing Checklist

Before TestFlight:

- Dynamic Type large accessibility size pass
- VoiceOver smoke pass
- Reduce Motion pass
- light/dark mode contrast pass
- widget tint/contrast pass
- paywall/legal readability pass
