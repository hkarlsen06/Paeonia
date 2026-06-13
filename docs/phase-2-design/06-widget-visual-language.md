# Widget Visual Language

The widget is a core product surface, not a secondary feature.

It should feel like a small private window between two people.

## Product Role

The widget should support:

- quick partner presence
- receiving a partner drawing
- opening the drawing experience quickly from the widget
- lightweight widget controls where the platform supports them
- showing calm shared state
- making distance feel active and mutual

## Visual Direction

The widget should be:

- low-clutter
- intimate
- drawing-first
- readable at a glance
- beautiful in tinted, dark, and light contexts
- consistent with the app icon and app palette once final colors exist

## Drawing Model

Drawings are stroke-based vector data in the app model.

Rules:

- store strokes as vector data
- rasterize on-device for network/storage efficiency where useful
- preserve enough stroke data to re-render at different widget sizes
- avoid flattening the canonical drawing to PNG only

## Platform Constraint

Home Screen widgets are not a freeform drawing canvas. The product should treat the app as the canonical drawing surface and the widget as the glanceable shared display.

Widget interactions may be used for supported lightweight actions, such as opening the drawing scene, clearing a local draft, or sending a simple reaction if that fits later. Continuous drawing gestures should not be designed as if they happen directly inside the widget unless Apple adds explicit support for that interaction model.

## Widget States

Required states:

- no partner yet
- paired but no drawing yet
- partner drawing available
- drawing sent, waiting for partner
- drawing draft available in app
- offline cached drawing
- sync failed
- subscription required, if applicable

## Empty Widget Tone

The empty widget should invite action without guilt.

Good:

```text
Draw something for them
```

Avoid:

```text
They are waiting for you
```

## Composition

The widget should reserve most visual space for the drawing.

Supporting elements should be small:

- partner initial/avatar placeholder
- timestamp/status
- subtle call to action

Do not turn the widget into a dashboard.

## Appearance Modes

The widget must be checked in:

- light mode
- dark mode
- tinted mode
- small widget size
- medium widget size, if supported
- lock screen/accessory contexts, if added later

## Future Design Dependency

Final widget colors should follow the app icon palette. Until then, use semantic tokens only.
