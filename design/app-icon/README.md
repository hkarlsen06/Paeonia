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

The selected concept is the delivered RM-02 app-icon mark, copied to `source/concepts/paeonia-app-icon-mark.svg`. It should feel intimate and premium without becoming childish or generic.

## Source Files

- `source/concepts/paeonia-app-icon-mark.svg`: original delivered SVG, including the plum rounded-square background.
- `source/concepts/paeonia-app-icon-mark-content.svg`: content-only SVG with the background removed, but still using the original full icon canvas.
- `source/concepts/paeonia-app-icon-mark-content-tight.svg`: content-only SVG cropped to the visible mark bounds. This is useful when an importer should see only the artwork.
- `source/concepts/paeonia-app-icon-mark-content-tight-square.svg`: content-only SVG on a tighter square canvas. Prefer this for Icon Composer if the tight non-square crop behaves awkwardly.

Design constraints:

- recognizable at small sizes
- no literal flower illustration
- no text
- no initials unless the mark earns it
- strong silhouette
- works in light, dark, tinted, and clear icon appearances
- emotional read: private, together, warm, resilient
