# Paeonia App Icon

Canonical source artwork for the Paeonia app icon.

## Pipeline

1. Design the icon as layered SVG source artwork.
2. Keep the source flat, opaque, and vector-based.
3. Do not bake in the iOS rounded-rectangle mask.
4. Export separate SVG layers for Icon Composer.
5. Use Icon Composer for final iOS 26 icon material, depth, and appearance tuning.
6. Export PNG previews only for review, marketing, or fallback assets.

## Structure

```text
design/app-icon/
├── source/
│   ├── concepts/      # Editable concept SVGs
│   └── layers/        # Icon Composer-ready layer exports
├── exports/
│   ├── icon-composer/ # .icon files or Icon Composer handoff assets
│   └── png/           # Generated preview/fallback PNGs
└── previews/          # Screenshots or rendered review previews
```

## Direction

The leading concept is an abstract peony mark made from two interwoven petals. It should feel intimate and premium without becoming childish or generic.

Design constraints:

- recognizable at small sizes
- no literal flower illustration
- no text
- no initials unless the mark earns it
- strong silhouette
- works in light, dark, tinted, and clear icon appearances
- emotional read: private, together, warm, resilient
