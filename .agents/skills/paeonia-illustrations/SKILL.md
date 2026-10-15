---
name: paeonia-illustrations
description: Make illustrated raster assets for the Paeonia iOS app with Codex image generation, in the house 3D sticker style, and import them into the asset catalog. Use for game hub card objects, props, tokens, and any picture where an object should look illustrated rather than drawn in code.
---

# Paeonia illustrations

Every illustration in the app looks like it came from one sticker set. You get that by holding four things fixed on every asset: the **style block**, a **style reference** from the approved set, the **checks**, and the **import**. Only the subject and its composition change.

Every asset is an **object**: one thing on a transparent background, such as a peony, a game disc or a game board, that code places and animates. The hub cards share one backdrop drawn in code (`GameHubBackdrop`), and each card places its game's objects on it. Read `docs/games/hub-artwork.md` before you brief objects for a hub card. It has the zones, the camera and the beats.

The approved set lives in `ios/PaeoniaApp/Resources/Assets.xcassets/GameHub/`. `GameHubPeony` and `GameHubConnectFourDiscPink` are the clearest examples of the object style, and `GameHubLudoBoard` and `GameHubStoryChainNotebook` of the hub card objects.

## Style block

Paste this word for word into every prompt. It is the source of truth for the design language, and `docs/games/hub-artwork.md` points here.

> Soft 3D illustration in the style of a premium iOS sticker set: chunky rounded forms, satin clay finish with soft glossy specular highlights, gentle subsurface glow, smooth gradients, no outlines, no texture noise. Palette: petal pink #F27EB2, deep pink #EF5094, rose #E85D86, blush white #FBF3F7, warm gold #F2B84B, lavender #B99CF2, sky blue #6FB1F0, plum #4F203A. Key light from the upper right, with a soft pink rim light on the upper-right edges and gentle shading toward the lower left. Isolated single object, centered, transparent background, no ground shadow, no text, no letters.

The light comes from the upper right because the app's pictures are lit from that corner (see `docs/games/hub-artwork.md`). Change the block only together with the standard, and regenerate the set when you do.

## Steps

### 1. Write the brief

For each asset, decide and write down:

- **Subject.** One object, named plainly: "a fountain pen", "a glossy game disc".
- **Composition.** The view and the anchor points code depends on. Ask for a strict front view, flat and evenly lit, for anything code draws on, like paper, a card face or a tile. Name where a tip or nib must be, such as "the nib tip is the lowest-left point of the object". Words, letters and numbers come from the String Catalog and are drawn in code, so the asset stays blank where they go.
- **Color.** Partner colors are fixed: pink #F27EB2 for the first player, lavender #B99CF2 for the second.
- **Display size.** The largest size in points the app shows it at. The import size is three times that.
- **File name.** Short and kebab-case for the original, such as `peony-bud.png`. The asset name is `GameHub<Game><Thing>`, or `GameHub<Thing>` when several games share it.

A hub card object's brief also names the camera and what the **beat** needs: the element left out for the app to animate, and the spot on the object where it lands. Ask for that spot's position in the object's pixels. Use this camera line for anything that lies flat, and a front view for things that stand upright:

> Camera: a three-quarter view from the front and above, the camera about 40 degrees above the table looking down at the object, centered, the object's front edge parallel to the bottom of the image. Every object in this set uses this same camera.

Done when every asset has all five, and every hub card object its camera and beat.

### 2. Generate

Codex generates with its built-in `image_gen` tool, one call per asset, in transparent background mode.

- Before the first call, load two approved assets with `view_image` and label them as style references, not edit targets. For a hub card object, load an approved hub card object too, for the camera. The prompt is then: the style block, then "Match the material, lighting and finish of the reference images.", then the subject and composition.
- Copy the chosen output from `$CODEX_HOME/generated_images/` to `/tmp/paeonia-art/<file name>`. Keep originals outside the repository.
- Regenerate an asset that breaks its composition, such as the wrong view, text in the image, a cropped edge or a misplaced tip, or that does not sit with the references. Two or three tries is normal.

A Claude agent hands this step to Codex with T3 `delegate_task`, on the `codex` provider with the newest Codex model. Paste the style block and every brief into the task, name `/tmp/paeonia-art/` as the output folder, say the repository must not change, and ask for the report from step 3. Run it `async`; one asset takes about a minute.

Done when every asset has a file in `/tmp/paeonia-art/`.

### 3. Check

Run the checker on every file (setup is in the script's header):

```bash
/tmp/paeonia-art-venv/bin/python -I .agents/skills/paeonia-illustrations/scripts/art_asset.py check /tmp/paeonia-art/*.png
```

It prints corner alpha, the share of pale fringe on the cutout's edge, and the object's bounds. It also writes `/tmp/paeonia-art-preview.png`, which shows every asset on the app's plum. Open the preview and look at each asset:

- a clean edge on plum, with no grey or white halo;
- the same finish and light as the references;
- the composition from the brief.

A white or cream object, like paper, reads as some fringe because its own edge is pale. Judge those by eye on the preview.

For a hub card, ask for two candidates of the main object and keep the better one. Compose the card on a render of the backdrop before you write code, with the objects at their planned places, and check it against the zones in `docs/games/hub-artwork.md`. Look at it next to the other cards: the same camera, the same size, the same light.

If you change the backdrop, render it and check the card's text against it. `text` lays the card frame's shadow and blur over it and checks every line against the contrast it needs:

```bash
/tmp/paeonia-art-venv/bin/python -I .agents/skills/paeonia-illustrations/scripts/art_asset.py backdrop /tmp/paeonia-art/backdrop.png
/tmp/paeonia-art-venv/bin/python -I .agents/skills/paeonia-illustrations/scripts/art_asset.py text /tmp/paeonia-art/backdrop.png
```

Done when every file prints `ok` (or passes by eye as a pale object) and looks right on the preview or on the backdrop.

### 4. Import

From the repository root, import each asset at three times its display size. A hub card object is sized in canvas pixels, so import it at 1.5 times its width on the canvas, which covers the widest phone and iPad cards:

```bash
/tmp/paeonia-art-venv/bin/python -I .agents/skills/paeonia-illustrations/scripts/art_asset.py import /tmp/paeonia-art/peony-bud.png GameHubPeonyBud 96
/tmp/paeonia-art-venv/bin/python -I .agents/skills/paeonia-illustrations/scripts/art_asset.py import /tmp/paeonia-art/ludo-board.png GameHubLudoBoard 900
```

Add `--opaque` for a full-bleed picture, which keeps the whole image and writes a JPEG. The size is the longest side. Add `--folder <Group>` for assets outside the games. The import trims the transparent margin, so the image's edges are the object's edges, and prints the final size and aspect ratio. Xcode generates the symbol, such as `Image(.gameHubPeonyBud)`.

Done when every asset is in the catalog.

### 5. Fit the code to the asset

Image generation never hits exact geometry. Asked for 4:3, the paper came out 1.22:1, and the "perfect circle" discs came out 1 percent wide. Measure the imported file, then size the code around it:

- Frame the image at its measured aspect ratio.
- Give anchor points as fractions of the image, measured from the pixels.
- Place a hub card object with `GameHubPlacement`, and its beat with `point(_:_:)` at fractions of the object. Codex reports the beat's position, but check it: draw a marker there on a crop of the object, and zoom in with a pixel grid for anything that must line up exactly, like the Connect Four holes or the strike line through three hearts. Then check it lands on the device.
- Every `Image` of an asset gets `.accessibilityHidden(true)` right after `.resizable()`, since the picture around it is already hidden from VoiceOver.

Done when the code uses measured numbers and SwiftLint is clean on the touched files.

## What the generator is good and bad at

- Good: single objects with a clear silhouette, such as flowers, pens, tokens, bottles, cards and discs. The style holds well across a set.
- Good: game boards and props for one series, with the camera line in every prompt. Twenty objects in one run came out as one set.
- Bad: two objects generated apart that must touch, such as a pawn standing on a board. Their cameras drift, and the piece looks pasted on. Cut the moving piece out of the main object's own image instead, with a mask drawn to its shape.
- Bad: code that follows painted geometry point by point. Animate one beat at one measured spot, such as a hole or a seam, instead of drawing on top of a painted grid.
- Bad: text. Even a requested blank face sometimes grows letters. Check every asset for them.
