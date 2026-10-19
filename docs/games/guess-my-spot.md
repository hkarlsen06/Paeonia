# Guess my spot

Design for the tenth game. One partner sends a photo from their camera roll, and the other drops a pin on a map where they think it was taken. The reveal flies from the guess to the real spot and scores by distance. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Guess my spot.

The name is "Guess my spot" in English and "Gjett hvor" in Norwegian.

Keep this file current. When a decision lands or the design changes, update it in the same change.

## Decisions

Decided by the developer on 2026-10-18 (the "Guess my spot" bullets in `docs/games-plan.md`).

- **Photos from the library.** The sender picks a photo from their camera roll. There is no camera button, because a couple who shares live location on the Home map would give a fresh photo away. Any age is fine. Memories are not a source.
- **The spot comes from the photo.** The phone reads the photo's location. When it has none or it is wrong, the sender drops the pin. The sender always sees the spot on a map before sending and can move it.
- **The picker stays open until sending.** The sender can swap the photo as often as they like until the round is sent. There is no skip.
- **The photo is stripped.** The phone removes the photo's metadata (camera, time, location) before uploading. The spot travels on its own and stays hidden from the guesser until they guess, as Consensio's spot does.
- **Turns like Consensio.** The partners take turns, one photo each. It plays async with pushes, and live when both are in the game.
- **Scoring by kilometres on a world scale.** Up to 5000 points, halving about every 1,500 km, as in GeoGuessr.
- **The guess screen.** The photo on the top half, pinch to look closer. The map on the bottom half to drop the pin. Apple's standard map in Paeonia's dark look, with a button for satellite.
- **The reveal.** The map zooms out from the guess, a gold line draws to the real spot, the camera lands there and the distance counts up. Then the photo comes back with the place name and date. Only "where" is guessed, not "when".
- **History.** "A map of our places": one shared map with a pin per round. Each pin opens its photo and both spots.
- **Name.** "Gjett hvor" in Norwegian.

Decided by the agent on 2026-10-18 while writing this file. The developer can change any of them.

- **The reveal's place name and date are hidden too.** Both would give the spot away, so the guesser's phone gets them only with the real spot.
- **The place name comes from the sender's phone.** Apple's reverse geocoding names the spot (such as "Bergen, Norway") on the check screen, and the name goes with the round. A send queued offline looks the name up just before it goes. When there is still no name, the reveal shows only the date.
- **The date is the day the photo was taken**, read from the photo's own data before it is stripped. A photo without one shows no date.
- **The sender's phone keeps no location access.** The game reads the location from the photo file, so it needs no location permission and no full photo library access.
- **Screenshots and videos are left out of the picker.** A screenshot has no place, and a video is not a photo.
- **A pin goes where you tap.** A tap on the map drops the pin, and the next tap moves it. Pinch and drag move the map. The map doesn't rotate or tilt, so north stays up.
- **The guess map starts on the whole world.** It gives no hint of a region.
- **Distances are metric in both languages.** Under 10 m the reveal shows whole metres, under 1 km tens of metres, under 10 km one decimal of a kilometre, and above that whole kilometres.
- **Sending counts toward the streak.** Guessing alone does not, as in Consensio, because the turn isn't done until you send yours.
- **The partner who opens the game first sends first.**
- **One push for a guess and a send.** As in Consensio, the result push waits 5 minutes, and a send in that window sends one push that covers both.
- **How to play cards.** Three cards, because "pick a photo, your partner guesses where" is not obvious from the picker.
- **Catalog order.** Right after Consensio, the other guessing game.

Decided by the developer on 2026-10-19, after the first build.

- **The play style decides the score.** "Together" shows one shared total. "Against each other" shows each partner's own points. Only the guesser scores a round. The server keeps both totals, so a change of style loses nothing.
- **A photo without a location opens near home.** The check map starts on the sender's own shared location, or on their phone's country when they share none, instead of on the whole world.
- **"Our guesses" clusters pins** that would overlap at the map's zoom.
- **Guessed rounds show on the Memories tab's "Our places" map,** with their photo, and their card says "From Guess my spot". They never count in its countries and cities.

Decided by the agent on 2026-10-19. The developer can change any of them.

- **The game's map is "Our guesses"** ("Gjetningene våre"), so it isn't confused with the Memories tab's "Our places".
- **The sender may delete a round they sent,** for both partners, once both have seen its reveal. The photo goes too. The points stay, because taking them back would change a score the partner already saw.

## Why this game

- It works across time zones. A turn takes a minute, and the reveal waits as long as it needs to.
- It is about the couple's own places: trips, home towns, the café from the first date. Each round is a memory the sender chose for the partner, and "Our guesses" keeps every one on a map. That is quality bar item 3.
- It needs no content to be written, so both languages get the same game from day one.

## The round

A couple has one ongoing game. A round has a sender and a guesser.

1. **Pick a photo.** The sender sees their camera roll in the screen and taps a photo.
2. **Check the spot.** The photo sits on the top half and the map on the bottom half, with a pin at the spot read from the photo, or a prompt to tap the map when the photo has none. A tap moves the pin. "Choose another photo" goes back to the camera roll, as often as the sender likes. "Send to [Name]" sends the round.
3. **Guess.** The guesser sees the photo on the top half and a map of the whole world on the bottom half. They tap where they think it was taken and tap "Lock in my guess".
4. **Reveal.** The camera travels from the guess to the real spot, the distance counts up and the points land. Then the photo comes back with the place name and date.
5. **Your turn to send.** The guesser picks the next photo. That is the next round.

The very first turn of a new game skips the guess and starts at "Pick a photo".

### Who acts

- The game's `turn_user_id` is the partner who acts next. While a round waits for a guess, it is the guesser. After the guess, it stays the same person, now as the next sender.
- The partner who isn't acting sees the waiting screen.
- A partner can see an unseen reveal at any time, whoever's turn it is.
- Both partners opening a new game at once is safe. `ensure_guess_my_spot_game` returns the game that already exists.

### The photo

- The picker is the system photo picker, shown inside the screen (`PhotosPicker` in its inline style), with one photo at a time and no screenshots or videos. It runs outside the app, so the app gets only the photo the sender taps and needs no photo library permission.
- The app reads the picked file's own data with ImageIO: the GPS latitude and longitude with their N/S and E/W references, and the day the photo was taken: the EXIF original date, else the digitized or TIFF date. A day after tomorrow counts as none, because a camera clock set wrong writes it and the server refuses it. A location of exactly 0, 0 counts as none, because broken cameras write it.
- The upload is a new JPEG drawn from the pixels, at most 2048 pixels on the long side, upright, at quality 0.82, with the quality lowered until it is under 4 MB. ImageIO writes only the pixels, their size and the color profile. A test checks that the file has no location, no date and no camera make or model.
- A photo the phone can't read shows "We couldn't open that photo. Try another one." and the picker stays.

### The spot

- A spot is a latitude from -90 to 90 and a longitude from -180 to 180, in degrees. The server rounds both to 6 decimals, about 10 cm.
- The check map opens on the spot at about 2 km across when the photo had one. When it didn't, the map opens about 40 km across on the sender's own spot from Home location sharing, or about 1,500 km across on the country of the phone's region (`MKGeocodingRequest`), or on the whole world when neither is known. Once the sender moved the pin, the line under the map says "Tap the map to move the pin." (`GuessMySpotHomeArea`.)
- The place name is the city with its country, or the nearest named place, as Apple's maps give it (`MKReverseGeocodingRequest`, the address's `cityWithContext`). It is looked up again each time the pin settles, and the line under the map shows it. The name sent is at most 120 characters. The same lookup gives the city alone (at most 80 characters) and the two-letter country code, which the memory map uses for a round's place.

### Distance

The distance is the great-circle distance between the guess and the spot, on a sphere of radius 6,371.0088 km (the haversine formula), in whole metres. The server computes it.

## Scoring

Points are `round(5000 × 0.5^(km / 1500))`, so every 1,500 km halves them.

| Distance | Points |
|---|---|
| 0 to 200 m | 5000 |
| 10 km | 4977 |
| 100 km | 4774 |
| 500 km | 3969 |
| 1,500 km | 2500 |
| 5,000 km | 496 |
| 20,000 km | 0 |

The verdict comes from the distance:

| Distance | Verdict |
|---|---|
| Up to 1 km | Spot on |
| Up to 25 km | So close |
| Up to 300 km | Close |
| More | Now you know where |

Each guess adds its points to the couple's shared total and to the guesser's own total. The play style picks which one shows. Both grow forever, like scores in other games, and deleting a round keeps its points.

## Live

Live runs whenever both partners have the game open. Without the partner there, everything works as async play.

- **Presence and roles.** While the screen is open, the phone joins the `guess_my_spot` relay room and says `hello` with one of the shared roles: `choosing` while picking and checking a photo, `watching` while guessing, `result` on a reveal, and `present` anywhere else. The partner's phone reads them as "picking a photo", "guessing" and "looking at the result". The Convex presence heartbeat runs next to it for push suppression.
- **The guess, live.** `GuessMySpotLiveMessage` has `roundID` and `guess`, a latitude and longitude, or none before the first tap. The guessing phone sends it on every tap and again when the sender arrives. The sender's waiting screen shows that pin on its map. Nothing in it is saved.
- **The real spot never goes over the relay.** The message type has no field for it, and the sending phone sends no message at all. A test checks the message type.
- **The reveal.** The guess goes to Convex. The guesser's phone opens the reveal at once and plays it as soon as the server answers with the real spot. The sender's phone plays it when the live feed delivers the guessed round.
- **Lost connection.** The relay reconnects as in Draw & Guess. The live pin fades out, and the status falls back to the async wording.
- **Invite.** The bell at the leading edge of the toolbar, with the shared invite rules.

## Async

- The sender sends and can leave. The guesser gets the turn push.
- The guesser locks in and sees the reveal at once. The sender gets the result push and sees the reveal next time.
- The sender may not open the game until the guesser has already sent the next photo. The game then shows the unseen reveal first, then "Your turn to guess".
- A send made offline is saved on the phone with its photo, and goes out when the phone is online. A guess made offline is saved too. The guesser can leave the held reveal, send the next photo, and leave. Both moves go out in order, and the reveal plays the next time the game opens.
- The server keeps when each partner first saw each reveal, so a second phone or a fresh install never plays an old reveal again.
- A turn that waits 72 hours gets one reminder, both for a guess and for a send.

## Streak

Sending a photo counts toward the couple's streak through `game_turn_completed`. The dedupe key is `game_turn_completed:<round id>:<user id>`.

## Notifications

`GAME_PUSH_COPY.guess_my_spot` in `lib/notificationCopy.ts`.

| Push kind | When | Title | Body |
|---|---|---|---|
| `game_turn_ready` | The partner sent a photo. | Your turn in Guess my spot / Din tur i Gjett hvor | Open Paeonia to guess where it was taken. / Åpne Paeonia for å gjette hvor bildet er tatt. |
| `game_turn_ready`, step `guessed` | The partner guessed your photo and sent one back within 5 minutes. | [Name] guessed and sent you a photo / [Name] har gjettet og sendt deg et bilde | Open Paeonia to see how close they got. / Åpne Paeonia for å se hvor nær gjetningen var. |
| `game_result` | The partner guessed your photo and sent nothing for 5 minutes. | [Name] made a guess / [Name] har gjettet | Open Paeonia to see how close they got. / Åpne Paeonia for å se hvor nær gjetningen var. |
| `game_invite` | Invite bell. | [Name] wants to play Guess my spot with you / [Name] vil spille Gjett hvor med deg | Shared invite body. |
| `game_turn_reminder` | The turn waited 72 hours. Once per turn. | Your turn in Guess my spot / Din tur i Gjett hvor | Shared reminder body. |

- Never show the photo, a place or the points. The payload holds only ids and the deep link `paeonia://games/guess-my-spot`.
- Skip the turn and result pushes while the recipient has the game open.
- `pushStillWanted` drops a turn push or a reminder once the turn moved on, and a result push once the sender saw the reveal, has the game open, or the next round was sent.

## History

"Our guesses" is one map with a pin for every guessed round, at the real spot.

- **Pins.** Each pin is the sender's pin (their color and drawn mark, as everywhere in the game). Tapping one opens the round.
- **Clusters.** Pins closer than about a ninth of the visible height and a sixth of the width join into one pin with a count, at the newest round's spot (`GuessMySpotClustering`). Tapping a cluster zooms in on its rounds. The zoom may go as close as 500 m across, so it always splits rounds more than 300 m apart. A cluster whose rounds are all within 300 m of each other opens a list sheet instead, because zooming would never split it.
- **Header.** A glass card over the top of the map: "12 places", then the score as the play style shows it. Together: the shared total, then each partner's closest guess and average. Against each other: each partner's own points with their closest guess and average ("Closest 120 m · On average 340 km").
- **Detail.** Tapping a pin opens a sheet with the photo (pinch to zoom), the place name and date, a small map with both pins and the line between them, "You sent this one" or "[Name] sent this one", and "[Name] guessed 3.2 km off · 4,993 points".
- **Delete.** The sender's detail has "Delete this photo" once both partners saw the reveal (`can_delete`). A confirmation says the partner won't see it anymore and the points stay. The round leaves the map at once and the delete goes through the pending operations. A refusal drops it with the shared banner, and the next read puts the round back.
- The map opens framing every pin. Only guessed rounds are listed, so an open round's spot never leaves the server. The server returns the newest 500.

### On the memory map

The Memories tab's "Our places" (`MemoriesMapScreen`) shows the same guessed rounds next to the memories, read from the same `GuessMySpotHistoryViewModel`.

- A round's pin is its photo, as a memory's is. Its card's second line is "From Guess my spot" instead of the place, and it opens the round's detail.
- Rounds never count in "4 countries · 11 cities", and the map's empty panel looks at memories only (`MemoriesMapContent.placedMemories`).
- A cluster that mixes memories and rounds counts "places" instead of "memories" in its badge label and list.
- Both maps follow the game's cache. They read the history again when the game's `version` changes (a guess, a seen reveal or a delete by either partner), and when a delete hidden on this phone leaves the queue, so a refused one comes back.

## Screens

Copy keys start with `guessMySpot.`, so their Swift symbols start with `guessMySpot`. The tables list only the part after `guessMySpot.`. "[Name]" is the partner's display name. Norwegian is Bokmål. Every string goes into the catalog with a translator comment.

### Shell

- One screen, `GuessMySpotScreen`, opened from the Games tab and from the pushes. It shows one phase at a time, picked by `GuessMySpotResolver` from the server's state, the queued moves, and what this person has seen.
- Look. `.paeoniaScreenBackground(.paeoniaBackgroundSecondary)`, `.preferredColorScheme(.dark)`, inline title "Guess my spot", dark toolbar.
- Toolbar trailing. The score capsule, which opens "Our guesses". Together: `heart.fill` and the shared total. Against each other: each partner's avatar with their own points. Then a `…` menu with "How to play". The invite bell sits at the leading edge while the partner is away.
- Phase change. Cross-fade plus a 12 pt rise over `PaeoniaMotion.meaningfulMoment`. Reduce Motion: cross-fade.
- A photo picked but not sent lives in the view model only. Leaving the screen keeps it until the app closes, so a look at "Our guesses" loses nothing.

### The map

`GuessMySpotMap` is the one map every phase shares.

- Apple's standard map, flat, muted, with no points of interest, in the dark color scheme. The satellite button in its top trailing corner switches to the hybrid satellite map with labels, and back. The choice is kept on this phone (`@AppStorage`).
- Pan and zoom only. A tap drops this person's pin or moves it.
- A pin (`GuessMySpotPin`) is Consensio's pin shape: a 36 pt round head on a thin stem, filled with its owner's color (`.boardGameMine` pink and `.boardGamePartner` lavender) with the owner's drawn mark or initial (`BoardMarkView`). The stem's foot is the spot.
- A drop plays `selection()` and `GameSound.tap` at 0.6. The pin appears at once: a map's pins don't take SwiftUI's animations.
- VoiceOver. The map is one element with the label "Map" and, where a tap drops a pin, the custom action "Drop the pin in the middle", which drops it at the center of the map. Its value is "Pin dropped" or "No pin yet". On "Our guesses" each pin is a button that reads its place and date.

### Haptics and sounds

Existing tokens and sounds only.

| Moment | Haptic | Sound |
|---|---|---|
| A photo picked | `selection()` | `tap` 0.7 |
| Pin dropped or moved, a pin on "Our guesses" tapped | `selection()` | `tap` 0.6 |
| Satellite button | `selection()` | `tap` 0.5 |
| Send, Lock in my guess | `drawingSent()` | `send` |
| Partner arrives, partner sent | `partnerDrawingReceived()` | `nudge` 0.6 |
| Reveal build-up, three beats | `streakTick(intensity:)` 0.3, 0.5, 0.7 | `tick` 0.4, 0.6, 0.8 |
| The real pin lands | `answerRevealed()` | `chime` |
| Distance counts up | `streakTick(0.3)` per step | `tick` 0.4 |
| Spot on | `streakCelebrated()` | `win` |
| So close, Close | `streakContinued()` | `bonus` |
| Now you know where | `partnerDrawingReceived()` | `soft` |
| Points count up | `streakTick(0.4)` per step | `tick` 0.5 |

### 1. Pick a photo

Layout, top to bottom.

1. Title "Pick a photo" (`title`), subtitle "Somewhere you've been. [Name] guesses where." The first turn of a new game says "Send a photo from somewhere you've been. [Name] guesses where it was taken." instead.
2. The inline picker fills the rest of the screen, with its own albums at the top. Its bottom bar is hidden, and one tap picks a photo.
3. The invite bell sits at the leading edge of the toolbar while the partner is away.

Tapping a photo plays `selection()` and `tap`, reads it, and opens the check. While the photo loads, a spinner covers the picker after 0.3 s.

| Key | English | Norwegian |
|---|---|---|
| `menu.a11y` | More options | Flere valg |
| `offline.message` | Connect to the internet to start the game. | Koble til internett for å starte spillet. |
| `pick.subtitle` | Somewhere you've been. %@ guesses where. | Et sted du har vært. %@ gjetter hvor. |
| `pick.subtitleFirst` | Send a photo from somewhere you've been. %@ guesses where it was taken. | Send et bilde fra et sted du har vært. %@ gjetter hvor det er tatt. |
| `pick.title` | Pick a photo | Velg et bilde |
| `pick.unreadable` | We couldn't open that photo. Try another one. | Vi fikk ikke åpnet det bildet. Prøv et annet. |
| `startFailed.message` | We couldn't start the game. Try again in a little while. | Vi fikk ikke startet spillet. Prøv igjen om litt. |
| `title` | Guess my spot | Gjett hvor |

### 2. Check the spot

Layout.

1. The photo on the top half, aspect fit on `.paeoniaSurfacePrimary`, rounded `radius16`.
2. The map on the bottom half, rounded `radius16`, with this person's pin.
3. Under the map: the title "Is this the spot?" once there is a pin, or "Where was this?" before. The hint is "We found it in the photo. Tap the map to move it." when the spot came from the photo, "This photo doesn't say where it was taken. Tap the map where it was." before a pin, and "Tap the map to move the pin." when the sender placed it, such as on a send that didn't go through and was put back. Under that, the place name with `mappin.and.ellipse` once there is a pin.
4. A quiet line: "We take the place and time out of the photo. [Name] only sees the picture."
5. Pinned bottom: primary "Send to [Name]" (`paperplane.fill`), off until there is a pin. Back in the toolbar reads "Choose another photo" and returns to the picker without sending.

"Send" fires `drawingSent()` and `send`, and the phase moves to waiting. Offline, the round is saved on this phone with its photo.

| Key | English | Norwegian |
|---|---|---|
| `check.another` | Choose another photo | Velg et annet bilde |
| `check.found.hint` | We found it in the photo. Tap the map to move it. | Vi fant det i bildet. Trykk på kartet for å flytte det. |
| `check.found.title` | Is this the spot? | Er dette stedet? |
| `check.moved.hint` | Tap the map to move the pin. | Trykk på kartet for å flytte nålen. |
| `check.missing.hint` | This photo doesn't say where it was taken. Tap the map where it was. | Bildet sier ikke hvor det er tatt. Trykk på kartet der det var. |
| `check.missing.title` | Where was this? | Hvor var dette? |
| `check.private` | We take the place and time out of the photo. %@ only sees the picture. | Vi tar sted og tid ut av bildet. %@ ser bare selve bildet. |
| `check.send` | Send to %@ | Send til %@ |
| `map.a11y` | Map | Kart |
| `map.dropCenter` | Drop the pin in the middle | Sett nålen midt på |
| `map.noPin` | No pin yet | Ingen nål ennå |
| `map.pinDropped` | Pin dropped | Nålen er satt |
| `map.satellite` | Satellite | Satellitt |
| `map.standard` | Map | Kart |
| `photo.a11y` | The photo. Pinch to look closer. | Bildet. Klyp for å se nærmere. |

### 3. Waiting

Two cases.

- **Waiting for the guess.** The photo I sent on the top half and the map on the bottom half, with my pin at the spot at 0.6 opacity. Live, the partner's pin appears where they tap, and the camera frames both pins. While the partner's pin is within 25 km, my pin shows at full strength and glows gold. Title "[Name] is guessing" while live, "Waiting for [Name]" otherwise.
- **Waiting for a photo.** The partner's avatar, 96 pt, with a breathing ring while they are in the game. Title "[Name] is picking a photo" while their role is `choosing`, "Waiting for [Name]" otherwise.

Under the title, a hint. Live: "You'll both see it the moment [Name] locks in." Away: "We'll tell you when [Name] guesses." or "We'll tell you when it's your turn." When the send is still on the phone after a failed try, the shared offline line shows, or "We couldn't send your move yet" with Try again. When the partner's photo arrives while this screen waits for it, the guess opens with `partnerDrawingReceived()` and `nudge`.

| Key | English | Norwegian |
|---|---|---|
| `wait.choosing` | %@ is picking a photo | %@ velger et bilde |
| `wait.guessing` | %@ is guessing | %@ gjetter |
| `wait.hintGuess` | We'll tell you when %@ guesses. | Vi sier fra når %@ har gjettet. |
| `wait.hintLive` | You'll both see it the moment %@ locks in. | Dere ser det begge så snart %@ har låst gjetningen. |
| `wait.hintTurn` | We'll tell you when it's your turn. | Vi sier fra når det er din tur. |
| `wait.partnerPin.a11y` | %@'s guess is on the map | Gjetningen til %@ er på kartet |
| `wait.title` | Waiting for %@ | Venter på %@ |
| `wait.yourSpot.a11y` | Your spot. Only you can see it. | Stedet ditt. Bare du ser det. |

### 4. Guess

Layout.

1. The live row (`GameLiveRow`): "[Name] is watching" with the accent ring while the sender is in the game, or "[Name] will see your guess later".
2. The photo on the top half, pinch and double tap to zoom (`PaeoniaZoomableImageView`). While it downloads, a spinner. When it can't be fetched, "We couldn't get the photo. Try again in a moment." with Try again.
3. The map on the bottom half, on the whole world, with the hint "Tap the map where you think it is." over it until the first pin.
4. Pinned bottom: primary "Lock in my guess" (`lock.fill`), off until there is a pin.

Lock in fires `drawingSent()` and `send`, and the reveal opens at once.

| Key | English | Norwegian |
|---|---|---|
| `guess.hint` | Tap the map where you think it is. | Trykk på kartet der du tror det er. |
| `guess.later` | %@ will see your guess later | %@ ser gjetningen din senere |
| `guess.lock` | Lock in my guess | Lås gjetningen |
| `guess.photoFailed` | We couldn't get the photo. Try again in a moment. | Vi fikk ikke hentet bildet. Prøv igjen om litt. |
| `guess.watching` | %@ is watching | %@ ser på |

### 5. Reveal

Purpose. The guesser sees how far their guess was from the real spot, and the sender sees how well their partner knows the place.

Both partners see the same reveal, always from the guess to the real spot. The guesser's phone plays it right after the guess. It starts from the map as they left it when the guess pin is in view and the map shows less than a continent, and otherwise on the guess at about 300 km across. The sender's phone starts on the guess at about 60 km across. The photo half slides up and away, and the map fills the screen. The map keeps the result card's height as bottom padding from the start, so every camera move frames the part of the map the card leaves, and nothing slides when the card rises. A map's pins and line don't take SwiftUI's animations, so the timeline steps the pulses, the line and the drop itself, reading the clock about 60 times a second.

Beats, in seconds after the reveal starts.

| Time | What happens |
|---|---|
| 0.00 | The photo slides up and fades out while the screen crosses over from the guess, and the map fills the screen (`meaningfulMoment`). The camera eases to its start over 0.25 s under that fade. The guess pin stands. On the guesser's phone the reveal waits here until the server answers. |
| 0.20, 0.45, 0.70 | Three build-up beats. The guess pin's head pulses 1 to 1.16 and back, each with `streakTick` and `tick`. |
| 0.90 | The camera zooms out over 0.9 s until both spots fit, with room around them. |
| 1.55 | The line draws from the guess toward the real spot along the great circle over 0.7 s, easing out: a 4 pt `.paeoniaInkGold` line on a 12 pt gold glow at 0.3, with square ends. A far guess draws a dashed 4 pt `.paeoniaTextSecondary` line instead, as in Consensio. |
| 2.30 | The real pin falls 70 pt onto the end of the line over 0.25 s. `answerRevealed()` and `chime` play as it hits, at 2.55. The map keeps 110 pt at its top for the distance capsule and the fall. The screen holds still for 0.3 s. |
| 2.85 | The camera lands on the real spot over 1.0 s, centered on it and wide enough that the guess stays in view (at least 1.5 km across). A far guess, which would need more than 400 km, stays on the view of both spots. The distance capsule appears at the top and counts up from 0 over 0.7 s in 10 steps, with plain digits and the width of the final number. |
| 3.60 | The verdict. Both heads glow gold over 0.3 s (0.8 for So close and Close, 1 for Spot on), a 4 pt gold ring widens from the real pin's head from 36 to 72 pt and fades over 0.4 s, and the distance capsule pulses 1 to 1.1 and back. Far has no glow or ring. See below. |
| 3.90 | The photo comes back: the result card rises 120 pt on a spring (0.3 s, bounce 0.1) with a 0.2 s fade, with the photo, the place name and date on it, the verdict title and line. |
| 4.20 | The shared total counts up over 0.7 s in 10 steps, with "+4,993" beside it. |
| 4.90 | The button appears. |

Verdict.

- **Spot on** (up to 1 km). Both heads spring 1 to 1.25 and back and glow gold, and a petal bloom bursts from the real pin (`GamePetalBloom`, intensity 3, seeded by the round id). `streakCelebrated()`, `win`. Title "Spot on!". Line "You found it." on the guesser's phone, "[Name] found it." on the sender's.
- **So close** (up to 25 km) and **Close** (up to 300 km). `streakContinued()`, `bonus`. Titles "So close!" and "Close". The line names the distance: "3.2 km off."
- **Now you know where** (more). The line is dashed from the start and the heads don't glow. `partnerDrawingReceived()`, `soft`. Title "Now you know where". Line "2,310 km off."

The result card. A `.paeoniaSurfaceSecondary` card on `radius28` over the bottom of the map. The photo fills its top, 180 pt tall (aspect fill, rounded `radius16`), with the place name in `bodyEmphasis` and the date in `caption` over a dark gradient at its bottom. Under the photo: the verdict title (`largeTitle`), the line (`body`, `.paeoniaTextSecondary`), and the score line. Together: both avatars, the counting total, "+points" and "points together". Against each other: each partner's avatar and own total, with "+points" beside the guesser's as it counts up.

Everything is tappable from 3.60. A tap jumps to the settled state, without repeating haptics. Reduce Motion: no pulses, zoom, line draw, drop, ring or bloom. The map shows both pins and the line framed together, the card is up, and only the verdict haptic and sound play.

Buttons. The guesser gets the primary "Your turn to send a photo". The sender gets "Continue", which goes to the guess when the partner already sent the next photo, and to waiting otherwise. Leaving the reveal marks it seen once its verdict has shown. A reveal left before the verdict plays again next time.

Held reveal. While the guess is on its way, the reveal holds at 0.00 with only the guess pin on the map. Once a send of the guess has failed, the line "Saved on this phone. We'll show where it was when you're online." shows (or, after a failure on a working connection, "We couldn't send your move yet" with Try again), with "Your turn to send a photo" under it. Stepping past a held reveal does not mark it seen. If the server refuses the guess because the round already has one, the screen plays the reveal of the guess the server has.

VoiceOver. On the verdict, one announcement: "Taken in Bergen, Norway. Your guess was 3.2 km off. So close. Points: 4,993." On the sender's phone: "Robin's guess was 3.2 km off. ..." Focus moves to the title. The bloom and line are hidden.

| Key | English | Norwegian |
|---|---|---|
| `handoff.continue` | Continue | Fortsett |
| `handoff.send` | Your turn to send a photo | Din tur til å sende et bilde |
| `reveal.announcement.guesser` | Your guess was %1$@ off. %2$@. Points: %3$@. | Gjetningen din var %1$@ unna. %2$@. Poeng: %3$@. |
| `reveal.announcement.place` | Taken in %@. | Tatt i %@. |
| `reveal.announcement.sender` | %1$@'s guess was %2$@ off. %3$@. Points: %4$@. | Gjetningen til %1$@ var %2$@ unna. %3$@. Poeng: %4$@. |
| `reveal.close.title` | Close | Nær |
| `reveal.far.title` | Now you know where | Nå vet du hvor |
| `reveal.off` | %@ off. | %@ unna. |
| `reveal.points` | +%@ | +%@ |
| `reveal.pointsTogether` | points together | poeng sammen |
| `reveal.soClose.title` | So close! | Så nær! |
| `reveal.spotOn.guesser` | You found it. | Du fant det. |
| `reveal.spotOn.sender` | %@ found it. | %@ fant det. |
| `reveal.spotOn.title` | Spot on! | Midt i blinken! |
| `reveal.waitingServer` | Saved on this phone. We'll show where it was when you're online. | Lagret på telefonen. Vi viser hvor det var når du er på nett. |

### 6. Our guesses

Entry points: the score capsule in the toolbar, and a quiet link on the hub card once the couple has a guessed round.

Empty states use `PaeoniaEmptyStateView`: no rounds yet (`map`, "No places yet", "Every photo you guess becomes a pin here."), and offline with nothing cached.

VoiceOver reads a pin as "Bergen, Norway, June 12, 2024". The detail reads as one card.

| Key | English | Norwegian |
|---|---|---|
| `history.delete` | Delete this photo | Slett dette bildet |
| `history.delete.confirm.action` | Delete | Slett |
| `history.delete.confirm.message` | %@ won't see it on the map anymore, and the photo is gone from Paeonia. Your points stay. | %@ ser det ikke på kartet lenger, og bildet er borte fra Paeonia. Poengene blir stående. |
| `history.delete.confirm.title` | Delete this photo for both of you? | Slette bildet for dere begge? |
| `history.detail.guess` | %1$@ guessed %2$@ off | %1$@ gjettet %2$@ unna |
| `history.detail.guessYou` | You guessed %@ off | Du gjettet %@ unna |
| `history.detail.sentBy` | %@ sent this one | %@ sendte dette |
| `history.detail.sentByYou` | You sent this one | Du sendte dette |
| `history.empty.message` | Every photo you guess becomes a pin here. | Hvert bilde dere gjetter, blir en nål her. |
| `history.empty.title` | No places yet | Ingen steder ennå |
| `history.failed.message` | We couldn't load your places. Try again in a little while. | Vi kunne ikke laste stedene deres. Prøv igjen om litt. |
| `history.offline.message` | Connect to the internet to see your places. | Koble til internett for å se stedene deres. |
| `history.places` | %lld place / %lld places | %lld sted / %lld steder |
| `history.records.average` | On average %@ | I snitt %@ |
| `history.records.closest` | Closest %@ | Nærmest %@ |
| `history.records.none` | No guesses yet | Ingen gjetninger ennå |
| `history.somewhere` | Somewhere | Et sted |
| `history.title` | Our guesses | Gjetningene våre |

### How to play

Three `GameTutorial` cards, opened the first time this phone opens the game and from the toolbar menu. Pictures in the `GameTutorial` asset folder, made with the `paeonia-illustrations` skill.

| Card | Picture | Title | Message |
|---|---|---|---|
| 1 (`GameTutorialGuessMySpotSend`) | An instant photo print of a sunny harbor, with a small pink pin beside it | Send a place / Send et sted | Pick a photo from somewhere you've been. We hide where it was taken. / Velg et bilde fra et sted du har vært. Vi skjuler hvor det er tatt. |
| 2 (`GameTutorialGuessMySpotGuess`) | A folded paper map with a lavender pin about to plant on it | [Name] guesses / [Name] gjetter | [Name] looks at the photo and drops a pin on the map. Then you swap. / [Name] ser på bildet og setter en nål på kartet. Så bytter dere. |
| 3 (`GameTutorialGuessMySpotClose`) | The map with both pins joined by a gold thread, a peony beside them | Closer means more points / Jo nærmere, jo flere poeng | The closer the pin, the more points. A pin right on the spot gives 5,000. / Jo nærmere nålen er, jo flere poeng. En nål midt på stedet gir 5 000. |

### Hub card

`GuessMySpotHubCard` follows the Consensio card: the picture behind the whole card, the partner-here chip and the score capsule over its scene, then the title, a status line, the primary button and the "Our guesses" link. The score capsule follows the play style, as the toolbar's does.

Artwork (`GuessMySpotHubArtwork`), following `docs/games/hub-artwork.md`. `GameHubGuessMySpotMap` is a folded paper map lying under the board camera, cream land and soft lavender water with a gold edge, about 600 pixels wide at the main object's spot, with an instant photo print leaning on its left side. The beat: `GameHubGuessMySpotPin`, a pink pin, drops onto the map's right half and plants with a small squash, and a gold glow swells under it.

| State | Status line | Button |
|---|---|---|
| No game yet | Send a photo. Then [Name] guesses where. | Play |
| My turn to send | Your turn to send a photo. | Send a photo |
| The partner sent, my guess | [Name] sent a photo. Your turn. | Guess |
| I sent, waiting | Waiting for [Name] to guess. | Open |
| The partner is picking | [Name] is picking a photo. | Open |
| Unseen reveal | A guess is in. | See how close |

"Your turn" (the badge and the glow) means a guess, a send or an unseen reveal waits for me.

| Key | English | Norwegian |
|---|---|---|
| `hub.guess` | Guess | Gjett |
| `hub.open` | Open | Åpne |
| `hub.play` | Play | Spill |
| `hub.seeReveal` | See how close | Se hvor nær |
| `hub.send` | Send a photo | Send et bilde |
| `hub.status.choosing` | %@ is picking a photo. | %@ velger et bilde. |
| `hub.status.guess` | %@ sent a photo. Your turn. | %@ har sendt et bilde. Din tur. |
| `hub.status.new` | Send a photo. Then %@ guesses where. | Send et bilde. Så gjetter %@ hvor. |
| `hub.status.reveal` | A guess is in. | En gjetning er klar. |
| `hub.status.send` | Your turn to send a photo. | Din tur til å sende et bilde. |
| `hub.status.waiting` | Waiting for %@ to guess. | Venter på at %@ skal gjette. |
| `pointsTogether` | %lld point together / %lld points together | %lld poeng sammen |
| `score.against.a11y` | You have %1$@. %2$@ has %3$@. | Du har %1$@. %2$@ har %3$@. |
| `stats.points` | %lld point / %lld points | %lld poeng |

### Wide layouts and Dynamic Type

- Wide (700 pt or more and wider than tall): the photo goes on the left half and the map on the right, for check, guess and waiting.
- Nothing on the photo and map screens scrolls, so the map's pan and pinch never fight a scroll view. Larger text takes its room from the photo and the map, and the button stays pinned.
- iPad keeps the tab bar.

## Names

| kind (backend, relay channel) | Swift prefix | URL path `paeonia://games/<path>` | Folder | Design doc |
|---|---|---|---|---|
| guess_my_spot | guessMySpot / GuessMySpot | guess-my-spot | GuessMySpot | docs/games/guess-my-spot.md |

## Data

The functions are in `backend/convex/guessMySpot.ts`, the rules and table definitions in `backend/convex/lib/guessMySpot.ts`.

- `guess_my_spot_games`: one row per couple. `turn_user_id`, `turn_started_at`, `turn_reminder_sent_at`, the shared total, `points_by_user` (each guesser's own total, as Draw & Guess keeps it), `round_count`, and `version`, which goes up with every change to the game or its rounds, seen marks included.
- `guess_my_spot_rounds`: one row per round. `round_number`, the sender, the guesser, `photo_media_asset_id` with the photo's `photo_width` and `photo_height`, `spot_latitude`, `spot_longitude`, `place_name`, `place_city`, `place_country_code`, `taken_on` (a calendar date, `YYYY-MM-DD`), `sent_at`, and once guessed, `guess_latitude`, `guess_longitude`, `distance_m`, `points`, `guessed_at`, `sender_reveal_seen_at` and `guesser_reveal_seen_at`. A deleted round keeps its row with `deleted_at`, and every read leaves it out. The client makes the round id, so a send queued offline can name its round and its photo upload.
- The game waits for a send when its newest round has a guess, or there is no round. It waits for a guess when its newest round has none.

The photo goes through the shared media upload with the reserved parent kind `guess_my_spot_round` (the round id) and the upload purpose `guess_my_spot_photo`, in the `couple-media` bucket, as a story photo does. A partner can read the photo once a round names it and while they can reach the couple's content (`canReadMediaAsset`). A round keeps its photo alive for the orphan sweep (`mediaAssetHasLiveReference`). The couple media sweep deletes the photos with the relationship.

Functions.

- `get_guess_my_spot` (query): the caller's view. The game, the newest round, and the one before it. `spot_latitude`, `spot_longitude`, `place_name`, `place_city`, `place_country_code` and `taken_on` go only to the sender of an open round, and to both on a guessed round. The game has `shared_points`, `my_points` and `partner_points`, and each round has `can_delete`. Returns `data_epoch: dataEpoch()`.
- `ensure_guess_my_spot_game`: makes the couple's game if there is none, with the caller sending first, and returns it either way.
- `send_guess_my_spot_photo` (client operation): `p_round_id`, `p_round_number`, `p_media_asset_id`, `p_latitude`, `p_longitude`, `p_place_name`, `p_place_city`, `p_place_country_code` and `p_taken_on` (all optional). Checks access before the replay check, that the caller sends next, the spot's range, the place name (1 to 120 characters after trimming, no control characters), the date (a real date, not after tomorrow), the round number, and that the photo is the caller's finalized `guess_my_spot_photo` upload reserved for this round and named by no other round. Opens the round for the partner, counts toward the streak, and queues the turn push (or the `guessed` step).
- `submit_guess_my_spot_guess` (client operation): `p_round_id`, `p_latitude`, `p_longitude`. Checks access before the replay check, then that the caller is the round's guesser and the round has no guess. Scores it, adds the points to the shared total and the guesser's own, queues the delayed result push, and returns the guessed round with the real spot. A repeat of the same guess returns the same answer.
- `mark_guess_my_spot_reveal_seen`: `p_round_id`. Keeps the first time. Safe to repeat.
- `get_guess_my_spot_history`: the newest 500 guessed rounds and `records`: `shared_points`, `my_points`, `partner_points`, and `mine` and `partner`, each `{ guesses, closest_m, average_m }` as a guesser, null before their first guess.
- `delete_guess_my_spot_round` (client operation): `p_round_id`. Checks access before the replay check, then that the caller sent the round and both partners saw its reveal. Marks the round deleted, bumps the game's `version`, and queues the photo for the orphan sweep. A repeat returns the first answer. Result `{ round_id, deleted_at }`.
- `guessMySpotBackend` in `lib/guessMySpot.ts` is the registry entry: `pushStillWanted`, `deleteCoupleRows` for both tables, and `sendDueTurnReminders`. It has no `onLanguageChanged`, because the game has no words.

Errors follow Consensio: `42501` for access, `23514` for rules ("this round already has a guess", "it isn't your turn", "latitude must be from -90 to 90", "photo is not usable"), `23505` for a repeat with different values.

## iOS

- **Folder.** `Features/Games/GuessMySpot/` with `Models/`, `Data/`, `Game/` (view model, resolver, rules with the distance and the great-circle path), `Photo/` (reading the location and date, stripping, the photo store, and the place name lookup), `Map/` (the map, the pin, the camera), `Screen/` (phases), `Reveal/` (timeline and script), `History/`, `Live/` and `Hub/`. Tests in `PaeoniaAppTests/Games/GuessMySpot/`.
- **Local first.** Sending, guessing and seen marks go into the pending operations before anything is sent (`SyncPendingOperationKind.guessMySpotSend`, `.guessMySpotGuess`, `.guessMySpotRevealSeen`, `.guessMySpotDeleteRound`). The stripped photo is written to `GuessMySpotPhotoStore` (Application Support, one file per person and round) before the send is queued, and the send handler reserves, uploads and finalizes it, then sends the round. After the server has the round, the photo moves to the shared media image cache under its asset id, so the sender never downloads their own photo. A send whose upload ran out queues again with new upload operations, as a Draw & Guess drawing does.
- **Order.** A send or a guess waits for every earlier send and guess of this person. A seen mark waits for the guess of its round. A refused send drops with the shared "Your move wasn't sent" banner and goes back to the check with its photo and pin. A guess refused because the round already has a guess reads the server's state and plays that reveal.
- **Cache.** `GuessMySpotCache` keeps the last `get_guess_my_spot` result and the last history, per person, in its own `GamesDocumentStore` file. It never takes a state behind the one it holds (a lower `version`), and `isOlder(than:)` is false across different `data_epoch` values.
- **Live feed.** `GuessMySpotLiveFeed` subscribes to `guessMySpot:get_guess_my_spot` and writes into the cache.
- **Live room.** One `WidgetLiveDrawing` connection on the `guess_my_spot` channel, for presence, roles and a `GameLiveChannel<GuessMySpotLiveMessage>`.
- **Memory map.** `GuessMySpotHistoryViewModel+MemoryMap.swift` turns guessed rounds into `MemoryMapEntry` values of kind `.guessMySpotRound`. `MainTabView+Tabs` hands the hub's history model to `MemoriesScreen`, which passes it to `MemoriesMapScreen`.
- **Privacy purge.** The purge clears the cache and the photo store. Downloaded photos are in the shared media image cache, which the purge already clears.
- **Registration.** `guess_my_spot` joins `GAME_KINDS`, `ALLOWED_CHANNELS` and `GameKind`. The relay deploys on its own, and a relay without the channel drops every live message for it, so the relay deploys before any build that opens the room.

### Developer scenarios

`App/DeveloperScenarios/DeveloperScenario+GuessMySpot.swift`, in this order. The fixtures are in `DeveloperGuessMySpotScenarios.swift` and `DeveloperGuessMySpotScenarioView.swift`. The two photos are `GuessMySpotScenarioHarbor` and `GuessMySpotScenarioLake` in the `GuessMySpotScenario` asset folder. The guesser-side reveals open on the guess screen with the pin dropped, and the server's answer arrives 2 seconds later, so the photo leaving and the build-up show as on a phone.

| id | Opens |
|---|---|
| `guess-my-spot-first-turn` | The picker of a new game |
| `guess-my-spot-check-found` | The check, with a photo that had a spot |
| `guess-my-spot-check-missing` | The check, with a photo that had none |
| `guess-my-spot-wait-choosing` | Waiting while the partner picks a photo |
| `guess-my-spot-wait-live` | Waiting for the guess, with the partner's pin moving |
| `guess-my-spot-wait-later` | Waiting for the guess, partner away, invite bell |
| `guess-my-spot-guess` | Guessing |
| `guess-my-spot-reveal-spot-on` | Reveal, about 460 m off, guesser side, from the guess screen |
| `guess-my-spot-reveal-close` | Reveal, about 110 km off, guesser side, from the guess screen |
| `guess-my-spot-reveal-far` | Reveal, Rome guessed for Bergen (about 2,100 km), guesser side, from the guess screen |
| `guess-my-spot-reveal-sender` | Reveal, about 9 km off, sender side |
| `guess-my-spot-reveal-held` | Reveal held: the guess is only on the phone and a send failed |
| `guess-my-spot-history` | Our guesses with 12 rounds, clustered |
| `memories-map-with-game` | The Memories tab's "Our places" with the memory fixtures and the 12 rounds |

## Open questions

- Whether the check screen needs a place search for photos without a location. The map now opens near home, which helps for photos from home but not from a trip.
