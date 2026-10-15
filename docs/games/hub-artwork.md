# Game hub artwork

Every game card on the Games tab, and on the Home tab while the partner is in a game, has a picture with the card's text on it (`GameHubCardFrame`). The picture is one painted backdrop that every card shares, with the game's illustrated objects placed on it in code. This file is the standard for those pictures. Check a new or changed card against every rule here before it ships. The shared code is in `Features/Games/Hub/GameHubArtworkParts.swift`, and the objects are made with the `paeonia-illustrations` skill.

## The series

The cards are one series, so the hub reads as one place:

- **One place.** The backdrop (`GameHubBackdrop`) is a room at night, so the objects stand somewhere real. Its left wall is lit pink and its right wall lavender, the two partners' worlds, and the corner where they meet is right behind the game's main object. The objects stand on the floor in front. The walls are bare, since a lone detail such as a window pulls the eye from the game. The room is clean and calm: no haze, no light rays, no bokeh, no sparkles and no mirror floor. That calm is what keeps the cards from looking like generated pictures.
- **Objects from one sticker set.** Every object is a separate image in the house 3D style, on a transparent background. Boards and paper lie under the same camera, three-quarter from the front and about 40 degrees above. Things that stand upright, like the Connect Four board and the Mind Meld cards, are seen from the front. The light comes from the upper right.
- **Few objects.** The main object and at most two props that belong to the game. No sparkles, stars, glitter or floating dots.
- **The same place for everything.** The main object stands at the same spot on every card, so the cards line up as you scroll.

## The canvas

A card's picture is laid out on a canvas of 1024 by 1536 pixels. It is as wide as the card and anchored at the top, so one pixel is `cardWidth / 1024` points (0.33 pt on the narrowest iPhone card). A card taller than the canvas continues in deep plum.

| Zone | Pixels from the top | What goes there |
|---|---|---|
| Badge | 0 to 200 | Only the backdrop's walls. The badge, such as the score, floats at the top center and ends at about 140 pixels on the narrowest card. Keep at least 60 pixels (about 20 pt) between it and any object. |
| Objects | 200 to 640 | The game's moment. The main object stands centered with its lower edge at 640, at most 440 pixels tall and about 510 to 600 wide. Props stand beside it with their lower edges at or above 640. Keep at least 110 pixels (about 36 pt) from both side edges, beats included. |
| Gap | 640 to 720 | Nothing. The backdrop starts going out of focus here, and the partner chip sits right under it. |
| Text | 720 to 1536 | The backdrop continues, out of focus, under the text. On it, centered: the partner chip when the partner is in the game, then the name, the status line, the button and the links. |

The card's text starts at 720 pixels at every width (`GameHubArtworkLayout.sceneShare`), so the scene keeps its shape on every phone and on iPad. Under the text the backdrop goes out of focus with a Gaussian blur (radius 20 pt), with a light plum shadow on top, 25 percent at the name and 50 percent at the bottom. Both fade in from 24 pt above the text to 16 pt into it. There is no frosted material and no color panel.

An object is placed with `GameHubPlacement`: the middle of its lower edge and its width, in canvas pixels, and its width divided by its height as the import measured it. `GameHubObject` draws it with a soft shadow right under its lower edge, so it stands on the floor. Props that lie on something else, such as a pen, go without the shadow.

## Contrast

- The text is checked against the backdrop under the frame's blur and shadow, line by line: the name at 3:1 (it is large and bold), and the status line and the links at 4.5:1. `art_asset.py text` simulates the frame on the backdrop image. The script holds the same numbers as `GameHubTextScrim` and `GameHubArtworkLayout`. Change them together.
- The status line is white, bold on your turn. Pink text can't keep 4.5:1 on a blurred pink backdrop without a heavy shadow, and the card's pink glow already marks your turn.
- The badge floats over the walls as Liquid Glass tinted 75 percent deep plum (`gameCapsuleStyle()`).
- The green partner chip sits on the blurred, shadowed part of the backdrop, where it stands out at more than 3:1.
- The main object stands out from the walls and floor behind it by at least 3:1. Cream, blush, gold and sky blue objects do. A dark object gets a light rim.

## The beat

The scene is the final frame of the game's moment, with one element left out. The app animates that element, so the card still moves where the game happens:

| Game | Objects | The beat |
|---|---|---|
| Draw & Guess | Paper with a pink heart doodle, a pencil | The letter tiles of the word pop in to the right of the paper |
| Mind Meld | Two blank word cards leaning together | A peony opens where their tops meet |
| Story Chain | A notebook page with lines, the pen, an ink bottle | A peony bud pops up after the last line |
| Connect Four | The board with every disc but the last, and the fifth column empty | The last pink disc drops down that column, and the row glows gold |
| Dots and Boxes | The board with its sunset boxes | A gold glow swells over the board |
| Ultimate Tic-Tac-Toe | The tray of boards with hearts and rings | A gold line strikes through three hearts |
| Odd Creatures | The folded strip with its creature, two crayons | A pink glow swells over the sweater's heart |
| Ludo | The board with one pawn of each partner and the dome empty | A pink pawn hops home onto the dome, and the dome glows gold |

- Measure the beat's spot on the object's pixels and give it as fractions of the image (`GameHubPlacement.point`), so it lands on the spot at every size.
- An element that moves across an object must share its camera. The Ludo pawn is cut out of the Ludo board image for that reason.
- The beat plays once when the card appears, within about 2 seconds. With Reduce Motion it shows the last frame.
- Words, such as the Draw & Guess letters, are drawn in code from the String Catalog. Objects have no text.

### The daily question card

The daily question card on the Home tab is in the same series (`DailyPromptHeroArtwork`, in `Features/DailyPrompt/`). It uses `GameHubCardFrame` with no partner chip, and the zones above hold:

| Card | Objects | The beat |
|---|---|---|
| Daily question | A sealed envelope, 560 pixels wide, standing at the main object's spot (lower edge at 640) | A wax seal with a peony presses onto the flap tip (0.495 across, 0.614 down the envelope), and a gold glow swells behind it |

- The seal is pink, this person's color. It is lavender once the partner has answered today, so the card reads as a letter from the partner. It is 150 pixels wide.
- The step count ("1 of 2 answered") is the top badge.
- When today's questions are done, the seal breaks (it lifts, turns and fades, with a gold flash) and the card shrinks to a short row with an open envelope. That row is not a hub card.

## Checklist

1. Open the hub with the `games-hub-partner-here` and `games-hub-board-games` developer scenarios, so the partner chip and the score badge show. Look at the cards on the narrowest iPhone and on iPad.
2. The zones hold: nothing under or near the badge, nothing past 640, nothing within 110 pixels of the sides.
3. `art_asset.py text` passes for the backdrop after any change to it.
4. The beat lands on its spot, and the last frame looks like one picture.
5. With Reduce Motion on, the card starts on its last frame.
6. The objects match the set: the same camera, the same light, the same finish.
