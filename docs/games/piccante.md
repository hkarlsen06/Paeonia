# Piccante

Piccante is the eleventh game. Each partner hides one chili in a shared chocolate box. Partners alternate bites. Every chili burns, including your own, and the person who bites one loses.

## Rules and decisions

The first opener starts. The starter chooses a 3 by 3, 4 by 4 or 5 by 5 box and hides first. The second hider bites first. Both chilis may share a chocolate. Hiding optionally includes a single-line note of 1 to 60 Unicode scalars. Empty means no note. A confirmed hide cannot change.

A tap selects and lifts a chocolate. Bite confirms it. Safe fillings are deterministic cosmetic choices. Once per game, before biting on their turn, a person may sniff an uneaten chocolate other than their own chili. Only they learn the answer. Norwegian uses "Lukt".

A burn pauses for half a second before the chili and its owner's drawn mark appear, followed by both chilis, both notes and the bite order. Shared positions get "Same one!". Reduce Motion shows the settled reveal. The loser reads the winner's note first. The winner reads the loser's note as what they would have received.

Either person may request a rematch. The previous nonstarter chooses the new size and starts. Keep the last unseen result through a rematch. Against each other shows lifetime wins. Together shows lifetime completed games. Hiding and each bite count toward the couple streak.

## Function contract

All paths use module `piccante`. All UUIDs normalize at the boundary. All reads and writes require entitled couple membership. Writes use client-operation idempotency, check access before replay, and return the caller's state projection. All move versions are exact `p_expected_version` values. Each client operation also carries `p_client_id`, `p_client_sequence` and `p_local_created_at` alongside its operation id, following the shared outbox contract. The envelope also returns `user_id`, `couple_id` and `partner_user_id`.

- Query `get_piccante({})` returns `{ data_epoch, game, unseen_result }`. Both game values are nullable.
- Mutation `ensure_piccante_game({})` returns that envelope, creating one game per couple with the caller as starter in `choosing`.
- Mutation `choose_piccante_size({p_game_id,p_expected_version,p_size,p_client_operation_id})` sets size to 3, 4 or 5, phase `hiding`, starter's turn.
- Mutation `hide_piccante_chili({p_game_id,p_expected_version,p_tile,p_note?,p_client_operation_id})` records a secret. After the second hide phase is `biting`, with the second hider's turn.
- Mutation `bite_piccante_chocolate({p_game_id,p_expected_version,p_tile,p_client_operation_id})` records a bite. Safe bites alternate; any chili ends the game.
- Mutation `sniff_piccante_chocolate({p_game_id,p_expected_version,p_tile,p_client_operation_id})` records this person's private one-use sniff without changing the turn.
- Mutation `start_piccante_rematch({p_game_id,p_expected_version,p_client_operation_id})` preserves the result and starts the next numbered game, in `choosing`, with the other starter.
- Mutation `mark_piccante_result_seen({p_game_id,p_game_number,p_client_operation_id})` marks only that completed game seen.
- Query `get_piccante_result({p_game_number})` returns a completed game projection for game chat.

Game projection keys: `id`, `game_number`, `version`, `starter_user_id`, `turn_user_id` nullable, `phase` choosing/hiding/biting/finished, `size` nullable, `my_chili` nullable integer, `my_note` nullable string, `partner_hidden` bool, `my_sniff` nullable `{tile,has_chili}`, `partner_sniff_used` bool, `bites` array `{tile,user_id}`, `chilis` array `{tile,user_id,note}` only when finished, `winner_user_id` nullable, `loser_user_id` nullable, `my_wins`, `partner_wins`, `games_finished`, `started_at`, `finished_at` nullable. No partner secret appears before completion. `unseen_result` is the latest finished game not seen by this person, including across rematches. Tile indexes are zero-based row-major.

## Screens and integration

Size choice, hiding with optional note, waiting, biting with selection and sniff, held queued bite, burn reveal and finished box. The game chat owns past results, with no separate history screen. The main screen uses shared presence, invite, reactions, attention, marks and tutorial components. The relay carries game number, version and selected tile only during biting, plus temporary reactions, never secrets. Offline hides and bites queue in the shared outbox. A sniff requires a connection. A queued bite never predicts its outcome.

The hub follows Ultimate Tic-Tac-Toe in the catalog. Its illustration is an open chocolate box with a warm glowing chocolate and small chili. Three tutorial cards teach hiding with a note, biting and own-chili danger, and the sniff. Every tile reads its row, column, filling, own chili and selection to VoiceOver. Extra controls open a native Board controls list.

## Visual presentation

The player header and score capsule reuse the board games' components. An absent partner has no presence subtitle. The shared portrait ring shows presence and handles the arrival pulse. Together shows completed games. The score opens the game chat, where the couple's past boxes live. The Games navigation root supplies the chat button too. Piccante has no separate history screen.

The box composes five transparent illustrations in the house 3D sticker style. Heart, drizzle and hazelnut chocolates share one overhead camera, gold cup and light. A bitten piece exposes cream filling, and the burned piece exposes chili filling. A checkmark identifies your lifted chocolate, and an arrow identifies your partner's. Chilis remain visible on your own piece, and a flame identifies the burned piece. Bite numbers and both owners' marks stay on the finished board. These shapes distinguish states without color.

The finished box becomes smaller to make room for the notes. The winning note leads on warm paper, with its recipient above the message and writer below it. The unused note is smaller and tinted lavender. Its heading describes the alternate outcome from the viewer's perspective. Both notes show immediately and wrap with Dynamic Type.

## Private sniff selection

Sniff opens its own private tile picker. It never reuses or broadcasts the lifted bite selection. Otherwise the partner could infer the sniffed tile when the used indicator appears. Closing the picker leaves the public bite selection unchanged. The partner learns only that a sniff was used.

## Storage and results

`piccante_games` keeps the current box and lifetime tallies. `piccante_results` keeps each completed box with per-person seen marks. Rematch marks the initiating person's old result seen atomically. The other person still sees the missed ending before continuing to the new box. The game chat references results by couple and game number. Downloads include the person's own hidden choices; partner notes stay out of personal exports.

The phone overlays queued operations in client order. Seen marks change per-person result metadata without advancing the game version. An offline bite holds its chocolate while the server decides the outcome. A stale move is dropped immediately, refreshes the authoritative box and shows the shared recovery banner. A stale rematch quietly loads the game the partner already started.

## Artwork and sound

The board pieces are `GameHubPiccanteHeart`, `GameHubPiccanteDrizzle`, `GameHubPiccanteNut`, `GameHubPiccanteBitten` and `GameHubPiccanteBurned`. Each transparent PNG is 450 pixels tall, with an aspect ratio between 0.993 and 0.996. They display at less than 150 points. The illustration skill's alpha and fringe checks pass for all five. The board draws only the tray and game-state overlays around those images.

The chosen second hub candidate imports at 900 by 622 pixels, aspect 1.447. Its 600-pixel canvas width puts its lower edge at 640. The warm beat sits over the front-right chocolate near 0.80 across and 0.70 down. Three separate tutorial stickers show the tucked note, the bitten chili and the sniff. All cutouts pass the illustration checker and were inspected on plum.

`PiccanteBite` is a short low chocolate crack with a soft body. `PiccanteBurn` is a low filtered swell with two warm notes. Recipes live in `ios/Scripts/game-sounds.swift`; generated CAF files use the shared ambient sound player.

## Developer scenarios

| Scenario | State |
|---|---|
| `piccante-choose` | Starter chooses the box size |
| `piccante-hide` | Hide one chili with an optional note |
| `piccante-biting` | Choose and confirm a bite |
| `piccante-partner-lifted` | Partner's live lifted chocolate |
| `piccante-sniff` | Private sniff answer and partner's used indicator |
| `piccante-burn` | Delayed burn reveal |
| `piccante-same-one` | Both chilis share a chocolate |
| `piccante-result` | Finished box, bite order and notes |

Piccante scenarios accept `-paeonia-scenario-piccante-size 3`, `4` or `5`, `-paeonia-scenario-piccante-compact YES` for a 320-point play area, `-paeonia-scenario-piccante-winner YES` for the winner's result perspective, and `-paeonia-scenario-piccante-together YES` for the shared completed-game count.

Pure iOS tests cover selection legality, one sniff, note scalars, restored epochs, held bites and queued seen/size/hide ordering. The UI journey checks that a successful private sniff preserves the public lifted chocolate. Backend tests cover access to every public function, rules, private projections, stale moves, idempotency, rematches, waiting keys and cleanup.
