# Guess my spot

Design for the tenth game. One partner sends a photo from their camera roll, and the other drops a pin on a map where they think it was taken. The reveal flies from the guess to the real spot and scores by distance. Shared rules for all games (transports, the Convex model, notifications, play style, game language, the streak) live in `docs/games-plan.md`. This file covers only what is specific to Guess my spot.

The name is "Guess my spot" in English and "Gjett hvor" in Norwegian.

Keep this file current. When a decision lands or the design changes, update it in the same change.

Activity rows are centered above the play area. Waiting titles keep the portrait beside the text, then stack it above the title at accessibility sizes.

## Decisions

Decided by the developer on 2026-10-18 (the "Guess my spot" bullets in `docs/games-plan.md`).

- **Photos from the library.** The sender picks a photo from their camera roll. There is no camera button, because a couple who shares live location on the Home map would give a fresh photo away. Any age is fine. Memories are not a source.
- **The spot comes from the photo.** The phone reads the photo's location. When it has none or it is wrong, the sender drops the pin. The sender always sees the spot on a map before sending and can move it.
- **The picker stays open until sending.** The sender can swap the photo as often as they like until the round is sent. There is no skip.
- **The photo is stripped.** The phone removes the photo's metadata (camera, time, location) before uploading. The spot travels on its own and stays hidden from the guesser until they guess, as Consensio's spot does.
- **Turns like Consensio.** The partners take turns, one photo each. It plays async with pushes, and live when both are in the game.
- **Scoring on a log scale.** Up to 5000 points, and every 10 times closer adds the same points. GeoGuessr's world scale (halving every 1,500 km) gave nearly every guess near home 4,950 or more, and most photos come from near home, so the street, the neighbourhood and the town now decide the round. (2026-10-27)
- **The guess screen.** A small photo on top that fills its frame, tap to see it full screen. The map under it takes most of the screen to drop the pin. Apple's standard map in Paeonia's dark look, with a button for satellite.
- **The reveal.** The map zooms out from the guess, a gold line draws to the real spot, the camera flies down close to it, and the distance counts up on the way. The guesser's reveal ends on the streets around the spot, however far the guess was, because the place is the sender's memory. The sender's reveal runs the other way, from their spot to the partner's guess, and ends on the streets around the guess, so it is a moment for both of them. Then the photo comes back with the place name and date. Only "where" is guessed, not "when".
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
- **One push for a guess and a send.** The result push waits 1 minute, and a send in that window sends one push that covers both. Consensio waits 5 minutes.
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
2. **Check the spot.** A small photo sits on top and the map takes most of the screen, with a pin at the spot read from the photo, or a prompt to tap the map when the photo has none. A tap moves the pin. "Choose another photo" goes back to the camera roll, as often as the sender likes. "Send to [Name]" sends the round.
3. **Guess.** The guesser sees a small photo on top and a map of the whole world under it. They tap where they think it was taken and tap "Lock in my guess".
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

Points are `round(5000 × log10(20,000 km / d) / log10(20,000 km / 25 m))`, with the distance `d` held between 25 m and 20,000 km. Every 10 times closer adds about 850 points. A guess within 25 m scores all of them, because a photo's own location is only good to a few metres.

| Distance | Points |
|---|---|
| 0 to 25 m | 5000 |
| 100 m | 4490 |
| 1 km | 3643 |
| 10 km | 2796 |
| 25 km | 2459 |
| 100 km | 1949 |
| 300 km | 1545 |
| 1,000 km | 1102 |
| 5,000 km | 510 |
| 20,000 km or more | 0 |

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
- **The guess map, live.** `GuessMySpotLiveMessage` has `roundID` and `view`, the map rect the guess map shows and whether it is the satellite map. The guessing phone sends it while the map moves, at most 30 times a second, always at the end of a move, when the satellite button switches, and when the sender arrives. The sender's waiting map shows that rect and that style, and can't be moved or switched while it follows. Nothing in it is saved. Decided by the developer on 2026-10-27.
- **The guess pin never goes over the relay.** The sender sees where the partner looks, not where they tap. The locked guess reaches the sender through Convex, in the reveal.
- **The photo, coming.** As soon as the sender picks a photo, their phone sends `photoPreview`: the round id the photo will make and the photo as a JPEG of at most 32 pixels on its longest side, made from the stripped photo. It sends it again when the guesser arrives, and `photoPreviewCleared` when the sender goes back to the picker. The guesser's phone drops a preview over 16 KB or 32 pixels, and drops the preview when the sender leaves without sending. Decided by the developer on 2026-10-27.
- **The real spot never goes over the relay.** No message has a field for a pin or a spot, and the preview is re-encoded without the photo's metadata. A test checks the message fields and that the preview has no location.
- **The reveal.** The guess goes to Convex. The guesser's phone opens the reveal at once and plays it as soon as the server answers with the real spot. The sender's phone plays it when the live feed delivers the guessed round.
- **Lost connection.** The relay reconnects as in Draw & Guess. The waiting map stays where the partner's map last was and can be moved again, and the status falls back to the async wording.
- **Invite.** The first item in the `…` menu, with the shared invite rules.

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
| `game_turn_ready` | The partner sent a photo. | Your turn in Guess my spot / Din tur i Gjett hvor | Guess where the photo was taken. / Gjett hvor bildet er tatt. |
| `game_turn_ready`, step `guessed` | The partner guessed your photo and sent one back within 1 minute. | [Name] guessed and sent you a photo / [Name] har gjettet og sendt deg et bilde | See how close they got. / Se hvor nær gjetningen var. |
| `game_result` | The partner guessed your photo and sent nothing for 1 minute. | [Name] made a guess / [Name] har gjettet | See how close they got. / Se hvor nær gjetningen var. |
| `game_invite` | Invite to play. | [Name] wants to play Guess my spot with you / [Name] vil spille Gjett hvor med deg | Shared invite body. |
| `game_turn_reminder` | The turn waited 72 hours. Once per turn. | Your turn in Guess my spot / Din tur i Gjett hvor | Shared reminder body. |

- Never show the photo, a place or the points. The payload holds only ids and the deep link `paeonia://games/guess-my-spot`.
- Skip the turn and result pushes while the recipient has the game open.
- `pushStillWanted` drops a turn push or a reminder once the turn moved on, and a result push once the sender saw the reveal, has the game open, or the next round was sent.

## History

"Our guesses" is one map with a pin for every guessed round, at the real spot.

- **Pins.** Each pin is the sender's pin (their color and drawn mark, as everywhere in the game). Tapping one opens the round.
- **Clusters.** Pins closer than about a ninth of the visible height and a sixth of the width join into one pin with a count, at the newest round's spot (`GuessMySpotClustering`). Tapping a cluster zooms in on its rounds. The zoom may go as close as 500 m across, so it always splits rounds more than 300 m apart. A cluster whose rounds are all within 300 m of each other opens a list sheet instead, because zooming would never split it.
- **Header.** A glass card over the top of the map: "12 places", then the score as the play style shows it. Together: the shared total, then each partner's closest guess and average. Against each other: each partner's own points with their closest guess and average ("Closest 120 m · On average 340 km").
- **Detail.** Tapping a pin opens a sheet with the photo (tap to see it full screen), the place name and date, a small map with both pins and the line between them, "You sent this one" or "[Name] sent this one", and "[Name] guessed 3.2 km off · 3,215 points".
- **Delete.** The sender's detail has "Delete this photo" once both partners saw the reveal (`can_delete`). A confirmation says the partner won't see it anymore and the points stay. The round leaves the map at once and the delete goes through the pending operations. A refusal drops it with the shared banner, and the next read puts the round back.
- The map opens framing every pin. Only guessed rounds are listed, so an open round's spot never leaves the server. The server returns the newest 500.

### On the memory map

The Memories tab's "Our places" (`MemoriesMapScreen`) shows the same guessed rounds next to the memories, read from the same `GuessMySpotHistoryViewModel`.

- A round's pin is its photo, as a memory's is. Its card's second line is "From Guess my spot" instead of the place, and it opens the round's detail.
- Rounds never count in "4 countries · 11 cities", and the map's empty panel looks at memories only (`MemoriesMapContent.placedMemories`).
- A cluster that mixes memories and rounds counts "places" instead of "memories" in its badge label and list.
- Both maps follow the game's cache. They read the history again when the game's `version` changes (a guess, a seen reveal or a delete by either partner), and when a delete hidden on this phone leaves the queue, so a refused one comes back.

## Open questions

- Whether the check screen needs a place search for photos without a location. The map now opens near home, which helps for photos from home but not from a trip.
