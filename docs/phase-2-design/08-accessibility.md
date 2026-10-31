# Accessibility

Accessibility is part of the design foundation. Paeonia handles private emotional content, so the app must be clear and comfortable for people using different input, vision, hearing, and motion settings.

## Baseline Requirements

- Support Dynamic Type on all core screens.
- Support VoiceOver labels for all controls and relationship-state content.
- Support Reduce Motion.
- Do not rely on color alone to communicate state.
- Keep tap targets at least 44x44pt.
- Maintain sufficient contrast in the canonical plum theme and any platform-driven tinted contexts.
- Provide text alternatives for icon-only controls.

## VoiceOver

Important elements need explicit labels:

- invite code controls
- relationship state
- check-in status
- memory media actions
- daily voice-answer controls
- drawing controls
- widget status where possible
- destructive actions

Avoid exposing decorative layout details to VoiceOver.

## Color And Contrast

The app uses one plum-led brand theme for MVP, but contrast rules still apply.

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

Daily voice answers are an MVP feature, so the UI should not assume audio is always available. Memory voice notes are not part of MVP.

MVP requirements:

- voice answers need clear playback controls
- playback state must be visible, not audio-only
- duration should be visible
- failed playback/upload states must be textual

Voice answers and chat recordings offer an author-entered transcript. Keep it with the recording through drafts, uploads, cached content, mutual reveal and export. External transcription needs an explicit consent flow. The [accessibility report](../accessibility-report.md) records the evidence and current label status.

## Drawing Accessibility

Drawing is expressive, but not every user can draw precisely.

The drawing experience should support:

- undo
- clear with confirmation when destructive
- simple stroke size/color controls
- large enough drawing controls
- clear sent/synced state

The native shape composer creates real PencilKit strokes through the same edit and undo paths as freehand drawing. Keep its position, size, color, replacement and removal controls available. Geometry readouts describe the supplied marks, never a hidden game answer or folded creature part. They do not recognize freehand objects.

Do not make drawing the only way to communicate a required action.

## Testing Checklist

Before TestFlight:

- Dynamic Type large accessibility size pass
- Complete the device-specific release gate in the accessibility report, including real VoiceOver and Voice Control journeys
- Reduce Motion pass
- plum theme contrast pass
- widget tint/contrast pass
- paywall/legal readability pass
