# Piccante

Piccante is the eleventh game. Each partner hides one chili in a shared chocolate box. Partners alternate bites. Every chili burns, including your own, and the person who bites one loses.

## Rules and decisions

Either partner may choose a 3 by 3, 4 by 4 or 5 by 5 box. Whoever commits the choice becomes the starter and hides first. Opening the game assigns no turn. While choosing, both partners see the size choices, nobody owes a move, and there is no turn badge, turn wait or reminder. An unseen previous result still waits to be opened. A competing size choice fails on its stale version and refreshes the chosen box. The second hider bites first. Both chilis may share a chocolate. Hiding optionally includes a single-line note about what the partner owes if they lose. Input removes control characters and caps the note at 60 Unicode scalars. The counter appears at 50 scalars. Empty means no note. A confirmed hide cannot change.

A tap selects and lifts a chocolate. Bite confirms it. The nine illustrated varieties use one deterministic assignment for both artwork and spoken names. Once per game, before biting on their turn, a person may sniff an uneaten chocolate other than their own chili. Only they learn the answer. Norwegian uses "Lukt på en".

The finishing bite swaps in the burned piece with a short shake, a haptic and the burn sound. About 0.4 seconds later, both chilis and their round owner avatars fade in. After another 0.24 seconds, the note and result actions slide up. The board keeps its size and the screen scrolls. Shared positions use the same "You both picked the same one!" headline for both people and a "Same one!" celebration. Reduce Motion shows the settled reveal. Each person sees only the note their partner wrote. The loser reads the winner's note as the note that counts. The winner reads the loser's note as what they escaped. If the partner wrote no note, no note card appears. This also applies to game-chat results and developer scenarios.

Either person may request a rematch. The previous nonstarter is the suggested chooser, but either person may choose and become the next starter. Keep the last unseen result through a rematch. Against each other shows lifetime wins. Together shows lifetime completed games. Hiding and each bite count toward the couple streak.

## Function contract

All paths use module `piccante`. All UUIDs normalize at the boundary. All reads and writes require entitled couple membership. Writes use client-operation idempotency, check access before replay, and return the caller's state projection. All move versions are exact `p_expected_version` values. Each client operation also carries `p_client_id`, `p_client_sequence` and `p_local_created_at` alongside its operation id, following the shared outbox contract. The envelope also returns `user_id`, `couple_id` and `partner_user_id`.

- Query `get_piccante({})` returns `{ data_epoch, game, unseen_result }`. Both game values are nullable.
- Mutation `ensure_piccante_game({})` returns that envelope, creating one game per couple in `choosing`, with the caller as the suggested chooser and no turn.
- Mutation `choose_piccante_size({p_game_id,p_expected_version,p_size,p_client_operation_id})` allows either member to set size to 3, 4 or 5. The chooser becomes the starter and takes the first hiding turn.
- Mutation `hide_piccante_chili({p_game_id,p_expected_version,p_tile,p_note?,p_client_operation_id})` records a secret. After the second hide phase is `biting`, with the second hider's turn.
- Mutation `bite_piccante_chocolate({p_game_id,p_expected_version,p_tile,p_client_operation_id})` records a bite. Safe bites alternate; any chili ends the game.
- Mutation `sniff_piccante_chocolate({p_game_id,p_expected_version,p_tile,p_client_operation_id})` records this person's private one-use sniff without changing the turn.
- Mutation `start_piccante_rematch({p_game_id,p_expected_version,p_client_operation_id})` preserves the result and starts the next numbered game, in `choosing`, with the other starter suggested and no assigned turn.
- Mutation `mark_piccante_result_seen({p_game_id,p_game_number,p_client_operation_id})` marks only that completed game seen.
- Query `get_piccante_result({p_game_number})` returns a game-chat projection. An unseen result omits its finishing bite, all chilis, notes, private sniff and outcome. The chat offers a link to Piccante to see the reveal.

Game projection keys: `id`, `game_number`, `version`, `starter_user_id`, `turn_user_id` nullable, `phase` choosing/hiding/biting/finished, `size` nullable, `my_chili` nullable integer, `my_note` nullable string, `partner_hidden` bool, `my_sniff` nullable `{tile,has_chili}`, `partner_sniff_used` bool, `bites` array `{tile,user_id}`, `chilis` array `{tile,user_id,note}` only when finished, `winner_user_id` nullable, `loser_user_id` nullable, `my_wins`, `partner_wins`, `games_finished`, `started_at`, `finished_at` nullable. No partner secret appears before completion. `unseen_result` is the latest finished game not seen by this person, including across rematches. Tile indexes are zero-based row-major.

## Screens and integration

Size choice, hiding with optional note, waiting, biting with selection and sniff, held queued bite, burn reveal and finished box. The game chat owns past results, with no separate history screen. The main screen uses shared presence, invite, reactions, attention and tutorial components. The relay carries game number, version and the public lifted tile only during biting. Reaction messages also carry that selection. It never carries chilis, notes or private sniff positions. Offline hides and bites queue in the shared outbox. A sniff requires a connection. A queued bite never predicts its outcome.

The hub follows Ultimate Tic-Tac-Toe in the catalog. Its illustration is an open chocolate box with a warm glowing chocolate and small chili. Three tutorial cards teach hiding with a note, biting and own-chili danger, and the sniff. Every uneaten tile reads its row, column and illustrated variety to VoiceOver. Eaten wrappers say "Eaten". Own chili, lifted selection, the partner's latest bite and private sniff marks add their spoken states. Extra controls open a native Board controls list.

The bite hint appears only before this person's first bite in the couple's first game. Waiting says whether the partner is hiding a chili or choosing a chocolate.

## Visual presentation

The Piccante player header shows plain round portraits above the names. It uses the shared avatar and presence ring without the board games' mark badges. The active portrait scales to 1.1 and turn changes animate unless Reduce Motion is enabled. Choosing emphasizes neither player. The hub and toolbar use the shared score capsule and hide empty scores. Unseen results withhold the score on the hub; a seen result says who won. An absent partner has no presence subtitle. The shared portrait ring shows presence and handles the arrival pulse. Together shows completed games. The score opens the game chat, where the couple's past boxes live. The Games navigation root supplies the chat button too. Piccante has no separate history screen.

The box composes nine whole chocolates in the house 3D sticker style. Pink heart, pink stripes, nut flower, dark gold drizzle, white truffle, pink rosette, square praline, white lavender stripes and lavender flower chocolates share one overhead camera, gold cup and light. Their arrangement uses the existing game seed and keeps identical chocolates apart horizontally and vertically at every box size. An eaten piece leaves the illustrated empty gold wrapper with crumbs, dimmed, desaturated and flattened without a lifted shadow. The burned piece exposes chili filling. Until this person lifts a chocolate, the partner's newest wrapper has their outline and small round avatar. An outline follows the illustration's alpha silhouette in the player's color. Lifted chocolates scale up, rise slightly and cast a soft shadow. The same treatment shows the partner's live selection. Differentiate Without Color adds a light outer outline, and Reduce Motion keeps the lift static. VoiceOver announces selection. Chilis remain visible on your own piece, and a flame identifies the burned piece. Both owners' round avatars stay on the finished board. Bite order has no badges. A small illustrated chili sticker replaces the emoji and sits above the owner avatars, clear of the chocolate. Owner avatars and the flame badge are at least 0.32 of a tile. These shapes distinguish states without color.

The finished box keeps its play size, with scrolling space for the note and actions. Only the partner's note appears, with its recipient above the message and writer below it. Both outcomes use one dark plum card with light text and a subtle folded corner. A losing partner's note describes what the winner escaped. The note slides up after the chili owners appear and wraps with Dynamic Type.

## Private sniff selection

Sniff opens its own private board picker. Extra controls keep a native list of available positions below the board. From Board controls, the picker presents inside that sheet. It never reuses or broadcasts the lifted bite selection. Otherwise the partner could infer the sniffed tile when the used indicator appears. Closing the picker leaves the public bite selection unchanged. The partner learns only that a sniff was used. After confirmation, the sniffed chocolate has a private check for safe or a flame with a warm glow for hot. Shapes distinguish these states without color. Neither the draft selection nor the confirmed tile goes over the relay.

## Storage and results

`piccante_games` keeps the current box and lifetime tallies. `piccante_results` keeps each completed box with per-person seen marks. Rematch marks the initiating person's old result seen atomically. The other person still sees the missed ending before continuing to the new box. The game chat references results by couple and game number. Downloads include the person's own hidden choices; partner notes stay out of personal exports.

The phone overlays queued operations in client order. Seen marks change per-person result metadata without advancing the game version. An offline bite holds its chocolate while the server decides the outcome. A stale move is dropped immediately, refreshes the authoritative box and shows the shared recovery banner. A stale rematch marks the previous game seen, without consuming a game version, then loads the game the partner already started. A failed seen write retries before the rematch leaves the outbox.

## Artwork and sound

The whole board pieces are `GameHubPiccanteHeart`, `GameHubPiccanteDrizzle`, `GameHubPiccanteNut`, `GameHubPiccanteGoldDrizzle`, `GameHubPiccanteWhiteTruffle`, `GameHubPiccanteRosette`, `GameHubPiccantePraline`, `GameHubPiccanteLavenderStripes` and `GameHubPiccanteFlower`. Eaten and burned tiles use `GameHubPiccanteWrapper` and `GameHubPiccanteBurned`. The chocolate PNGs have a 450-pixel longest side. `GameHubPiccanteChili` is a 96 by 88 transparent sticker, generated with the illustration skill and checked on plum at marker size. The wrapper is square, and the chocolate aspect ratios are between 0.980 and 1.009. They display at less than 150 points. The illustration skill's alpha and fringe checks pass for all eleven. The board draws only the tray and game-state overlays around those images.

The chosen second hub candidate imports at 900 by 622 pixels, aspect 1.447. Its 600-pixel canvas width puts its lower edge at 640. The warm beat sits over the front-right chocolate near 0.80 across and 0.70 down. Three separate tutorial stickers show the tucked note, the bitten chili and the sniff. All cutouts pass the illustration checker and were inspected on plum.

## Sounds

The developer selected these CC0 recordings by ear, including the Freesound HQ previews. Freesound sources use lossy HQ MP3 previews, not the original downloads. Bite D uses the original BigSoundBank WAV. All prepared WAVs are mono 44.1 kHz signed 16-bit PCM, normalized to about -3 dBFS. Import changes only the container to CAF, preserving the PCM samples. These files are recordings, not recipes. `ios/Scripts/game-sounds.swift` writes only its synthesized recipe outputs and leaves recordings untouched.

The shared player randomly picks among five bite variants without consecutive repeats. Bite plays at 0.30 on the Bite tap and on the partner's replayed bite, without repeating this person's bite on the server response. Burn plays at 0.30 at the start of the staged reveal. Lift replaces the shared tap at 0.18 when this person selects a chocolate. A successful private sniff plays at 0.20. Queuing a hide plays at 0.22. The Same one chime plays at 0.18 when its reveal appears. Reduce Motion skips replay and reveal sounds as before. The audio session stays ambient. The silent switch mutes game sounds. A partner's lift over this person's chili still plays only its heartbeat haptic.

Common bite processing was extraction, downmix, resampling, DC removal, second-order 40 Hz high-pass, 2 ms fade-in, 18 ms fade-out and peak normalization to -3 dBFS. No pitch shift, layering, time stretch, reverb or synthetic mouth sound was added to the bites. The rice-cake source already includes its author's mix.

### GameSoundPiccanteBite1.caf

Imported from `bites/bite-a.wav`.

- Source: https://freesound.org/people/ursenfuns/sounds/535012/
- Author: ursenfuns
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Crunchy Bite
- Download: https://cdn.freesound.org/previews/535/535012_166713-hq.mp3
- Edits: source interval 0.340 to 0.940 s; common bite processing listed above.

### GameSoundPiccanteBite2.caf

Imported from `bites/bite-b.wav`.

- Source: https://freesound.org/people/black_trillium/sounds/752128/
- Author: black_trillium
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Eating A Biscuit or Cookie
- Download: https://cdn.freesound.org/previews/752/752128_4889106-hq.mp3
- Edits: source interval 1.670 to 2.230 s; common bite processing listed above.

### GameSoundPiccanteBite3.caf

Imported from `bites/bite-c.wav`.

- Source: https://freesound.org/people/SammygoodTunes/sounds/844811/
- Author: SammygoodTunes
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: crunch
- Download: https://cdn.freesound.org/previews/844/844811_8175347-hq.mp3
- Edits: source interval 0.045 to 0.565 s; common bite processing listed above.

### GameSoundPiccanteBite4.caf

Imported from `bites/bite-d.wav`.

- Source: https://bigsoundbank.com/manger-une-biscotte-s0407.html
- Author: Joseph SARDIN
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Eat a Rusk
- Download: https://bigsoundbank.com/UPLOAD/bwf-en/0407.wav
- Edits: source interval 0.040 to 0.600 s; common bite processing listed above.

### GameSoundPiccanteBite5.caf

Imported from `bites/bite-e.wav`.

- Source: https://freesound.org/people/Anthousai/sounds/398756/
- Author: Anthousai
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: apple - bite 01.wav
- Download: https://cdn.freesound.org/previews/398/398756_5923045-hq.mp3
- Edits: source interval 0.860 to 1.440 s; common bite processing listed above.

### GameSoundPiccanteBurn1.caf

Imported from `burn.wav`.

- Source page: https://freesound.org/people/bottles/sounds/382313/
- Author: bottles
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Sizzle / Acid Burn
- Download used: lossy Freesound HQ MP3 preview, not original. https://cdn.freesound.org/previews/382/382313_460876-hq.mp3
- Edits: Extracted source interval 0.120 to 1.320 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteLift1.caf

Imported from `lift.wav`.

- Source page: https://freesound.org/people/golovlev.sound/sounds/632220/
- Author: golovlev.sound
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: paper, thin, tracing, blueprint, rustle.wav
- Download used: lossy Freesound HQ MP3 preview, not original. https://cdn.freesound.org/previews/632/632220_3784464-hq.mp3
- Edits: Extracted source interval 3.650 to 4.070 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteSniff1.caf

Imported from `sniff.wav`.

- Source page: https://freesound.org/people/spookymodem/sounds/202101/
- Author: spookymodem
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Sniffing.wav
- Download used: lossy Freesound HQ MP3 preview, not original. https://cdn.freesound.org/previews/202/202101_3756348-hq.mp3
- Edits: Extracted source interval 1.640 to 1.870 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteHide1.caf

Imported from `hide.wav`.

- Source page: https://freesound.org/people/Mafon2/sounds/360646/
- Author: Mafon2
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Paper drawn with rustle
- Download used: lossy Freesound HQ MP3 preview, not original. https://cdn.freesound.org/previews/360/360646_1196472-hq.mp3
- Edits: Extracted source interval 1.020 to 1.320 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteSameOne1.caf

Imported from `same-one.wav`.

- Source page: https://freesound.org/people/Seth_Makes_Sounds/sounds/852531/
- Author: Seth_Makes_Sounds
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Bell Sound
- Download used: lossy Freesound HQ MP3 preview, not original. https://cdn.freesound.org/previews/852/852531_13228046-hq.mp3
- Edits: Extracted source interval 0.000 to 0.700 s; downmixed to mono; removed DC; 70 Hz high-pass and 4800 Hz low-pass, both second-order; layered a second recorded hit at +160 ms, resampled to about a major third higher; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

## Developer scenarios

| Scenario | State |
|---|---|
| `piccante-choose` | Either partner chooses the box size |
| `piccante-choose-second` | The second opener also sees the choices |
| `piccante-hub` | Isolated hub card with an unseen result |
| `piccante-sniff-hot` | Private flame mark on the sniffed chocolate |
| `piccante-hide` | Hide one chili with an optional note |
| `piccante-biting` | Choose and confirm a bite |
| `piccante-partner-lifted` | Partner's live lifted chocolate |
| `piccante-sniff` | Private sniff answer and partner's used indicator |
| `piccante-burn` | Delayed burn reveal |
| `piccante-same-one` | Both chilis share a chocolate |
| `piccante-result` | Finished box and the partner's note |

Piccante scenarios accept `-paeonia-scenario-piccante-size 3`, `4` or `5`, `-paeonia-scenario-piccante-compact YES` for a 320-point play area, `-paeonia-scenario-piccante-winner YES` for the winner's result perspective, and `-paeonia-scenario-piccante-together YES` for the shared completed-game count.

Pure iOS tests cover selection legality, one sniff, note scalars, restored epochs, held bites and queued seen/size/hide ordering. The UI journeys check that a successful private sniff preserves the public lifted chocolate and that sniffing opens from Board controls. The pending-operation regression covers a lost rematch race without consuming a game version. Backend tests cover access to every public function, rules, private projections, stale moves, idempotency, rematches, waiting keys and cleanup.
