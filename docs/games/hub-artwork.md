# Game hub artwork

Every game card on the Games tab, and on the Home tab while the partner is in a game, is one painting with the card's text on it (`GameHubCardFrame`). This file is the standard for those paintings. Check a new or changed painting against every rule here before it ships. The shared code is in `Features/Games/Hub/GameHubArtworkParts.swift`, and the paintings are made with the `paeonia-illustrations` skill.

## The series

The cards are one series, so the hub reads as one place. Every painting uses the same idea, camera and light:

- **Two places.** Deep plum night, with two big, soft, curved color fields behind the game: petal pink on the left and lavender on the right, the two partners' worlds. They meet in a soft seam right behind the game's main object, so the game is what joins them.
- **Graphic and bold.** Flat editorial shapes (arcs, hills, a huge soft moon or sun) with large 3D objects in front, in the house style.
- **Few objects.** The main object, at most two props that belong to the game, and nothing else. No sparkles, stars, glitter or floating dots. The painting earns attention with its objects, its shapes and its one moment.
- **Same camera, same light.** The objects sit at the same height in every painting, lit from the upper right. Vary the shapes a little per game so the cards are not copies of each other.

## Composition

A card is one designed picture, not objects placed on a gradient. These rules are the core of the standard:

- **Use the full height.** The picture starts at the top edge. The color fields, a big soft shape or the main object reach the top. Nothing sits over the top of the card, so an empty band there is dead space.
- **One focal point.** The main object fills 70 to 90 percent of the width, centered, with its visual center about a quarter of the way down the painting (around pixel 360). The seam between the pink and lavender worlds runs behind it and leads the eye to it.
- **Balance.** The weight is centered and calm. A prop on one side is answered by a shape, a light or a smaller element on the other, and the two top corners hold quiet shapes of similar weight.
- **Depth in three planes.** Back: the two color worlds and one big soft shape. Middle: the main object standing on a surface. Front: that surface coming toward the viewer in full color, with soft reflections of the main object, and one small prop or the main object's lower edge overlapping into it.
- **The picture continues under the text.** Below the scene the surface and the color fields carry on in full, mid-tone color down to the bottom, a little darker at the very bottom, smooth and low in detail. The text sits on that part of the picture, not on a panel.
- **Negative space on purpose.** Soft gradients and big shapes, never a flat empty area.
- **Few objects.** Covered under the series: the main object and at most two props.

## The canvas

A painting is 1024 by 1536 pixels. The card shows it as wide as the card and anchored at the top, so one pixel is `cardWidth / 1024` points (0.33 pt on the narrowest iPhone card). A card taller than its painting continues in deep plum.

| Zone | Pixels from the top | What goes there |
|---|---|---|
| Scene | 0 to 640 | The game's moment. The main object and its props. Everything that must read sharp sits above 560. The badge, such as the score, floats at the top center, so keep the top center a big calm shape (the moon in the current series) with no detail. |
| Text | 640 to 1536 | The picture continues, out of focus, under the text. On it, centered: the partner chip when the partner is in the game, then the name, the status line, the button and the links. Smooth, mid-tone color, nothing lighter than about #C0608A, and nothing the scene needs. |

The card's text starts at 640 pixels at every width (`GameHubArtworkLayout.sceneShare`), so the scene keeps its shape on every phone and on iPad. Under the text the painting itself goes out of focus with a Gaussian blur (radius 20 pt), with a light plum shadow on top, 25 percent at the name and 50 percent at the bottom. Both fade in from 24 pt above the text to 16 pt into it. There is no frosted material and no color panel: you see the painting, blurred.

The text block is centered, under the centered scene, so the card stays balanced.

## Contrast

- The text is checked against the painting under the frame's blur and shadow, line by line: the name at 3:1 (it is large and bold), and the status line and the links at 4.5:1. `art_asset.py text` in the skill simulates the frame and measures this. The shadow's strength lives in `GameHubTextScrim` and the blur in `GameHubArtworkLayout`, and the script holds the same values. If a painting fails, calm or darken its lower part rather than raising the shadow for every card.
- The status line is white, bold on your turn. Pink text can't keep 4.5:1 on a blurred pink painting without a heavy shadow, and the card's pink glow already marks your turn.
- The badge floats over the painting as Liquid Glass tinted 75 percent deep plum (`gameCapsuleStyle()`). No solid color stands out from both the dark sky and the bright moon behind it (their relative luminance runs from 0.06 to 0.68), but the glass's light rim reads on the dark parts and its dark tint on the bright ones, and its light text keeps more than 4.5:1.
- The green partner chip sits on the blurred, shadowed part of the painting, where it stands out at more than 3:1.
- The main object stands out from what is behind it by at least 3:1. Cream, blush, gold, pink and lavender objects do on plum. A dark object, like a game board, gets a light rim.

## The beat

A painting is the final frame of the game's moment, with one element left out. The app animates that element on top, so the card still moves where the game happens:

| Game | Painted | The beat |
|---|---|---|
| Draw & Guess | Paper with a pink heart doodle and a pencil | The letter tiles of the word pop in, in the clear right third |
| Mind Meld | Two blank word cards leaning together | A peony opens where they meet |
| Story Chain | A written page, the pen, an ink bottle | A peony bud pops up after the last line |
| Connect Four | The board with every disc but the last | The last pink disc drops into its hole, and the row glows gold |
| Dots and Boxes | The board with its sunset boxes | A gold glow swells behind the board |
| Ultimate Tic-Tac-Toe | The boards with their hearts and rings | A gold line strikes through three hearts |
| Exquisite Corpse | The folded strip with its creature | A pink glow swells behind the sweater's heart |

- Leave the beat's spot clear and simple in the painting, and measure its position in the painting's pixels. The beat is laid out in those pixels (`GameHubArtwork`, `GameHubBeatPop`, `GameHubBeatGlow`), so it lands on the spot at every card width.
- The beat plays once when the card appears, within about 2 seconds. With Reduce Motion it shows the last frame.
- Words, such as the Draw & Guess letters, are drawn in code from the String Catalog. Paintings have no text.

## Checklist

1. Open the hub with the `games-hub-partner-here` developer scenario, so the partner chip shows, and with a game that has a badge. Look at the card at 335 pt and on iPad.
2. The composition rules hold: full height, one focal point, balance, three planes, and the picture continuing under the text.
3. `art_asset.py text` passes for the painting.
4. The beat lands on its spot, and the last frame looks like the painting was made with it.
5. With Reduce Motion on, the card starts on its last frame.
6. The painting matches the series: two color fields, the seam behind the main object, the same camera and light.
