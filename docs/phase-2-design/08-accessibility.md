# Accessibility

Paeonia holds private emotional content, so it must work for different input, vision, hearing and motion settings. The task and device matrix, evidence and release gate are in [the accessibility report](../accessibility-report.md).

## Rules

- Dynamic Type on all core screens. No fixed-height containers around text, no truncated emotional or legal text, and `minimumScaleFactor` only on constrained visual elements such as widgets and countdowns.
- VoiceOver labels on every control and on relationship-state content. Hide decorative layout.
- Never rely on color alone for state.
- Tap targets at least 44x44 pt.
- Primary and secondary text and accent buttons keep readable contrast on the plum theme and in tinted contexts.
- Reduce Motion skips decorative animation and keeps state changes clear.

## Audio

Do not assume audio is available. Voice answers have visible playback controls, playback state and duration, and failed playback or upload shows text. Voice answers and chat recordings offer an author-entered transcript. Keep it with the recording through drafts, uploads, cached content, mutual reveal and export. External transcription needs an explicit consent flow.

## Drawing

Drawing offers undo, a confirmed clear, simple size and color controls, and a clear sent state. The native shape composer creates real PencilKit strokes through the same edit and undo paths as freehand drawing, with position, size, color, replacement and removal controls. Geometry readouts describe only the supplied marks, never a hidden answer. Drawing is never the only way to communicate a required action.
