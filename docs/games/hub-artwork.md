# Game hub artwork

Every game card on the Games tab, and on the Home tab while the partner is in a game, is one painting with the card's text on it (`GameHubCardFrame`). This file is the standard for those paintings. Check a new or changed painting against every rule here before it ships. The shared code is in `Features/Games/Hub/GameHubArtworkParts.swift`, and the paintings are made with the `paeonia-illustrations` skill.

## The series

The cards are one series, so the hub reads as one place. Every painting uses the same idea, camera and light:

- **Two places.** Deep plum night, with two big, soft, curved color fields behind the game: petal pink on the left and lavender on the right, the two partners' worlds. They meet in a soft seam right behind the game's main object, so the game is what joins them.
- **Graphic and bold.** Flat editorial shapes (arcs, hills, a huge soft circle) with large 3D objects in front, in the house style. The main object fills 60 to 80 percent of the width and may be cut off by the left or right edge.
- **Few objects.** The main object, at most two props that belong to the game, and nothing else. No sparkles, stars, glitter or floating dots. The painting earns attention with its objects, its shapes and its one moment.
- **Same camera, same light.** The objects sit at the same height in every painting, lit from the upper right. Vary the shapes a little per game so the cards are not copies of each other.

## The canvas

A painting is 1024 by 1536 pixels. The card shows it as wide as the card and anchored at the top, so one pixel is `cardWidth / 1024` points (0.33 pt on the narrowest iPhone card). A card taller than its painting continues in deep plum.

| Zone | Pixels from the top | What goes there |
|---|---|---|
| Chip band | 0 to 160 | The green partner chip on the left and the blush badge on the right. Calm and mid-dark: no objects, no detail, no highlights. |
| Scene | 160 to 640 | The game's moment. The main object and its props. |
| Text | 640 to 1536 | The name, the status line, the button and the links. The color fields continue down, calmer and darker, and reach deep plum by about 1000. No objects and no detail. |

The card's text starts at 640 pixels at every width (`GameHubArtworkLayout.sceneShare`), so the scene keeps its shape on every phone and on iPad. The frame blurs and darkens the painting under the text. The fade starts 24 pt above the text and is complete 16 pt into it, so keep the scene above 560 pixels sharp and important.

## Contrast

- The chip band's brightest point has a relative luminance of at most 0.09, about #6A2E52. That keeps both chips at 3:1 or more: the green partner chip (relative luminance 0.39) and the blush badge (0.90). The frame turns every badge blush on the hub through `gameCapsuleStyle()`.
- The text scrim is dark plum at 0.7 on a dark blur, so white text keeps more than 4.5:1 even where a pink field runs under it. Keep the text zone calm anyway: detail under a blur still reads as noise.
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
| Exquisite Corpse | The folded strip with its creature | Not built yet |

- Leave the beat's spot clear and simple in the painting, and measure its position in the painting's pixels. The beat is laid out in those pixels (`GameHubArtwork`, `GameHubBeatPop`, `GameHubBeatGlow`), so it lands on the spot at every card width.
- The beat plays once when the card appears, within about 2 seconds. With Reduce Motion it shows the last frame.
- Words, such as the Draw & Guess letters, are drawn in code from the String Catalog. Paintings have no text.

## Checklist

1. Open the hub with the `games-hub-partner-here` developer scenario, so the partner chip shows, and with a game that has a badge. Look at the card at 335 pt and on iPad.
2. The chip band is calm, and its brightest point is at most 0.09 relative luminance. `art_asset.py zones` in the skill measures it.
3. The beat lands on its spot, and the last frame looks like the painting was made with it.
4. The text reads cleanly on the blur, and nothing important hides under it.
5. With Reduce Motion on, the card starts on its last frame.
6. The painting matches the series: two color fields, the seam behind the main object, the same camera and light.
