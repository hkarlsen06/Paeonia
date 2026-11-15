# Widget visual language

The widget is a core product surface, a small private window between two people. It is low-clutter, drawing-first, readable at a glance, and holds up under iOS widget tinting and accessibility appearance changes.

## Platform constraint

Home Screen widgets are not a freeform drawing canvas. The app is the drawing surface and the widget is the glanceable shared display. Widget interactions are limited to lightweight supported actions such as opening the drawing scene. Do not design continuous drawing gestures into the widget.

## Drawings

Drawings are stroke-based vector data. Rasterize on-device where useful for storage and network, but keep enough stroke data to re-render at every widget size. Never flatten the canonical drawing to PNG only.

## Tone

The empty widget invites without guilt. "Draw something for them" is right. "They are waiting for you" is not.

## Composition

Most of the space belongs to the drawing. Supporting elements (partner initial, timestamp or status, a subtle call to action) stay small. Do not turn the widget into a dashboard.

Check tinted mode and every supported size. Widget colors follow the app palette through semantic tokens.
