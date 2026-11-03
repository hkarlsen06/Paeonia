# Game hub artwork

Every game card on the Games tab, and on the Us tab while the partner is in a game, has a picture with the card's text on it (`GameHubCardFrame`, which uses the shared `PaeoniaIllustratedCard`). The picture is the game's illustrated objects, placed in code on a slowly moving backdrop in the colors of that same picture, like the background behind a song in Apple Music. This file is the standard for those pictures. Check a new or changed card against every rule here before it ships. The shared code is in `Features/Games/Hub/GameHubArtworkParts.swift`, and the objects are made with the `paeonia-illustrations` skill.

## The series

The cards are one series, so the hub reads as one place:

- **A backdrop from the card's own picture.** Behind each game card is a 3 by 3 mesh gradient (`GameHubFluidBackdrop`) in four colors taken from the card's picture (`GameHubPalette`). The app draws the scene's last frame small, skips transparent, grayish and dark pixels, and takes the average color of the most common bands of hue, each at least 30 degrees from the others. A picture with fewer than four hues fills the rest with deeper shades of its own colors, so the backdrop never shows a color the picture lacks. Pastel colors are made more saturated and gold is turned to amber, since both look dusty or olive once they are dark. The bottom row of the mesh is half as bright, because the text sits there. The mesh's inner points sway slowly, each with its own period between 8 and 14 seconds, at up to 30 frames a second. It stands still with Reduce Motion and while the app is in the background, and it crossfades when the picture changes. A picture with too few colored pixels gets the pink and lavender fallback. The app keeps every palette for the session (`GameHubPalettes`), so a card that scrolls back into view does not read its picture again. Each card's colors differ because its objects differ, so the series comes from the objects and the camera, not from a shared room. There is no haze, no light rays, no bokeh, no sparkles and no floor. That calm is what keeps the cards from looking like generated pictures.
- **The daily question card keeps the room.** `GameHubBackdrop` is a painted room at night, its left wall lit pink and its right wall lavender, with a floor in front. Only the daily question card uses it, and it is out of focus under that card's text.
- **Objects from one sticker set.** Every object is a separate image in the house 3D style, on a transparent background. Boards and paper lie under the same camera, three-quarter from the front and about 40 degrees above. Things that stand upright, like the Four in a Row board and the Mind Meld cards, are seen from the front. The light comes from the upper right.
- **Few objects.** The main object and at most two props that belong to the game. No sparkles, stars, glitter or floating dots.
- **The same place for everything.** The main object stands at the same spot on every card, so the cards line up as you scroll.

## The canvas

A card's picture is laid out on a canvas of 1024 by 1536 pixels. It is as wide as the card and anchored at the top, so one pixel is `cardWidth / 1024` points (0.33 pt on the narrowest iPhone card). A game card's backdrop fills the whole card. The daily question card's room ends in deep plum, so that card continues in deep plum below the canvas.

| Zone | Pixels from the top | What goes there |
|---|---|---|
| Badge | 0 to 200 | Only the backdrop. The badge, such as the score, floats at the top center and ends at about 140 pixels on the narrowest card. Keep at least 60 pixels (about 20 pt) between it and any object. |
| Objects | 200 to 640 | The game's moment. The main object stands centered with its lower edge at 640, at most 440 pixels tall and about 510 to 600 wide. Props stand beside it with their lower edges at or above 640. Keep at least 110 pixels (about 36 pt) from both side edges, beats included. |
| Gap | 640 to 720 | Nothing. The partner chip sits right under it. |
| Text | 720 to 1536 | The backdrop continues under the text. On it, centered: the partner chip when the partner is in the game, then the name, the status line, the button and the links. |

The hub's grid shows most games as small tiles, about 160 pt wide on iPhone, with the same picture and beat. The canvas scales down with the tile, so the zones above hold there too. A tile has no badge, so the badge zone stays empty. Once the couple has played a game, its tile shows their latest content instead of the objects and beat: the board, the last drawing, the finished creature, the Guess my spot photo, the Mind Meld words, the story or the Consensio scale (`GameChatPreviewContent`, the same drawing as in the chat). It stands at the main object's spot like an album cover, as a 640 pixel square with its lower edge at 676, rounded by 64 pixels, with a drop shadow (`GameHubTileContent`). There is no frame or rim. The square is deep plum at 55 percent, so the backdrop shows through it. The backdrop's colors come from the content: from the loaded image for a drawing, a creature or a photo, and from the drawn content for everything else. Only public boards and revealed content go there (`GameChatPreviewLoader`).

The hub's full cards, under "Right now" and "Today's pick", use a shorter variant (`PaeoniaIllustratedCardLayout.Scene.hubBanner`), so the first card and the next card's name fit on one iPhone screen. The picture shows the canvas from 110 to 520 pixels: the empty badge zone above is cut away, and the text starts at 520. The objects shrink to 70 percent toward the middle of the main object's lower edge, which lands at 464, so the main object's top stays about 45 pixels below the card's edge. The badge moves to the top left corner, 12 pt from both edges, beside the objects instead of above them. The Us tab card and the daily question card keep the whole scene.

On every other card the text starts at 720 pixels at every width (`PaeoniaIllustratedCardLayout.Scene.full`), so the scene keeps its shape on every phone and on iPad. Under the text lies a light plum shadow, 25 percent at the name and 50 percent at the bottom, which fades in from 24 pt above the text to 16 pt into it. On the daily question card the room also goes out of focus there with a Gaussian blur (radius 20 pt). The mesh needs no blur, since it is already smooth. There is no frosted material and no color panel.

An object is placed with `GameHubPlacement`: the middle of its lower edge and its width, in canvas pixels, and its width divided by its height as the import measured it. `GameHubObject` draws it with a soft shadow right under its lower edge, so it does not float. Props that lie on something else, such as a pen, go without the shadow.

## Contrast

- `GameHubPalette` caps every color's relative luminance at 0.14 when it makes the palette, so no picture can make the text faint. At that cap the status line, blush at 74 percent under the lightest part of the plum shadow (25 percent), keeps 4.5:1 on any hue, and white text gets 5.5:1. The name (3:1, large and bold) and the links (4.5:1) have more room. `GameHubPaletteTests` checks the status line against palettes made from bright pictures. Change the cap, the shadow and the test together.
- On the daily question card, the text is checked against the room under the frame's blur and shadow, line by line, with the same numbers. `art_asset.py text` simulates the frame on the room image, with the text at 720 pixels and at the hub card's 520. The script holds the same numbers as `PaeoniaIllustratedCardLayout` and `GameHubBackdrop`. Change them together.
- The status line is white, bold on your turn. Pink text can't keep 4.5:1 on a pink backdrop without a heavy shadow, and the card's pink glow already marks your turn.
- The badge floats over the backdrop as Liquid Glass tinted 75 percent deep plum (`gameCapsuleStyle()`).
- The green partner chip sits on the shadowed part of the backdrop, where it stands out at more than 3:1.
- The main object stands out from the backdrop behind it. The mesh is never brighter than the cap, so cream, blush, gold and sky blue objects stand out by far more than 3:1. A dark object gets a light rim. `art_asset.py text` checks a cream object against the room's wall for the daily question card.

## The beat

The scene is the final frame of the game's moment, with one element left out. The app animates that element, so the card still moves where the game happens:

| Game | Objects | The beat |
|---|---|---|
| Draw & Guess | Paper with a pink heart doodle, a pencil | The letter tiles of the word pop in to the right of the paper |
| Mind Meld | Two blank word cards leaning together | A peony opens where their tops meet |
| Story Chain | A notebook page with lines, the pen, an ink bottle | A peony bud pops up after the last line |
| Four in a Row | The board with every disc but the last, and the fifth column empty | The last pink disc drops down that column, and the row glows gold |
| Dots and Boxes | The board with its sunset boxes | A gold glow swells over the board |
| Ultimate Tic-Tac-Toe | The tray of boards with hearts and rings | A gold line strikes through three hearts |
| Odd Creatures | The folded strip with its creature, two crayons | A pink glow swells over the sweater's heart |
| Ludo | The board with one pawn of each partner and the dome empty | A pink pawn hops home onto the dome, and the dome glows gold |
| Consensio | A cream rail with gold end caps and one pink pin planted in it | A lavender pin drops onto the rail beside it and plants, and a gold glow swells between the two heads |
| Guess my spot | A folded paper map with lavender water and a gold edge, an instant photo of a harbor leaning on its left side | A pink pin drops onto the map's right half and plants with a small squash, and a gold glow swells under it |

- Measure the beat's spot on the object's pixels and give it as fractions of the image (`GameHubPlacement.point`), so it lands on the spot at every size.
- An element that moves across an object must share its camera. The Ludo pawn is cut out of the Ludo board image for that reason.
- The beat plays once when the card appears, within about 2 seconds. With Reduce Motion it shows the last frame.
- Words, such as the Draw & Guess letters, are drawn in code from the String Catalog. Objects have no text.

### The daily question card

The daily question card on the Us tab is in the same series (`DailyPromptHeroArtwork`, in `Features/DailyPrompt/`). It uses the shared `PaeoniaIllustratedCard` directly, with no partner chip, and the zones above hold:

| Card | Objects | The beat |
|---|---|---|
| Daily question | A sealed envelope, 560 pixels wide, standing at the main object's spot (lower edge at 640) | A wax seal with a peony presses onto the flap tip (0.495 across, 0.614 down the envelope), and a gold glow swells behind it |

- The seal is pink, this person's color. It is lavender once the partner has answered today, so the card reads as a letter from the partner. It is 150 pixels wide.
- The step count ("1 of 2 answered") is the top badge.
- The envelope holds the partner's answers, so it opens only once they can be read. When today's questions are done and the partner has answered, the seal breaks (it lifts, turns and fades, with a gold flash), the flap folds back, a letter rises in the pocket, and the card shrinks to a short row with the same open envelope. If the partner has not answered yet, the card shrinks with the envelope still sealed, and the short row opens it the same way when the partner answers. That row is not a hub card. The envelope is cut along the flap's rim in `PaeoniaEnvelope.swift`, which the first-day gift uses too.

## Checklist

1. Open the hub with the `games-hub-partner-here` and `games-hub-board-games` developer scenarios, so the partner chip and the score badge show, and `games-hub-quiet` for the tiles with the couple's content. Look at the full cards and the grid tiles on the narrowest iPhone and on iPad.
2. The zones hold: nothing under or near the badge, nothing past 640, nothing within 110 pixels of the sides. On a hub card the badge in the corner keeps clear of the objects.
3. The backdrop's colors come from the card's own picture, differ from its neighbors' when the objects differ, and keep the objects standing out. After a change to the palette, the cap or where the text starts, `GameHubPaletteTests` passes, and `art_asset.py text` passes for the daily question card's room.
4. The beat lands on its spot, and the last frame looks like one picture.
5. With Reduce Motion on, the card starts on its last frame and the backdrop stands still.
6. The objects match the set: the same camera, the same light, the same finish.
