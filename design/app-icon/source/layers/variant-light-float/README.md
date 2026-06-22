# Light Float Variant

Experimental Icon Composer layer split.

## Goal

Make the lighter petal shapes feel like a floating surface above a darker unified flower mark.

## Files

- `base-darkened.svg`: base mark where the original light-pink paths are recolored to the darker petal color.
- `light-float.svg`: only the original light-pink paths, aligned to the same square artboard.
- `composite-preview.svg`: flat preview of the base plus floating light layer.

PNG fallbacks are exported to:

```text
design/app-icon/exports/png/variant-light-float/
```

## Icon Composer Order

1. Set the background separately in Icon Composer, usually plum `#380F27`.
2. Import `base-darkened.svg`.
3. Import `light-float.svg` above it.
4. Give `light-float.svg` slightly more height/depth than the base.

If Icon Composer refuses SVG imports, use the matching `*-1024.png` exports instead.
