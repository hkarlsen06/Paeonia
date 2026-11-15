# Motion and haptics

Motion is calm, fast, purposeful, interruptible and respects Reduce Motion. Avoid decorative motion that delays a task. Most interactions stay under 0.3 seconds. Durations live in `PaeoniaMotion.swift`.

## Reduce Motion

No parallax, large animated transitions or looping decorative movement. Keep opacity and scale changes minimal and the state clear.

## Haptics

Use them sparingly, through `PaeoniaHaptics`, never directly from feature views. None fires repeatedly while browsing. Key moments (pairing, shared answer reveal, memory saved, milestones) may be stronger than ordinary controls. Never use strong haptics for retention pressure or streak anxiety. Showing a destructive confirmation has no haptic.

## Drawing

Drawing feedback is immediate. Do not animate strokes in a way that changes the user's intent. Sending feels lightweight. A received drawing may animate in subtly, but must not feel like a social media notification.

## Celebration

Only for moments that matter: pairing accepted, first shared prompt reveal, first memory, anniversary or milestone. No confetti by default. Use softer visual language.
