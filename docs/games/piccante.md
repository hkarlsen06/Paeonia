# Piccante

Piccante is the eleventh game. Each partner hides one chili in a shared chocolate box. Partners alternate bites. Every chili burns, including your own, and the person who bites one loses.

## Rules and decisions

Either partner may choose a 3 by 3, 4 by 4 or 5 by 5 box. Whoever commits the choice becomes the starter and hides first. Opening the game assigns no turn. While choosing, both partners see the size choices, nobody owes a move, and there is no turn badge, turn wait or reminder. An unseen previous result still waits to be opened. A competing size choice fails on its stale version and refreshes the chosen box. The second hider bites first. Both chilis may share a chocolate. Hiding optionally includes a single-line note about what the partner owes if they lose. Input removes control characters and caps the note at 60 Unicode scalars. The counter appears at 50 scalars. Empty means no note. A confirmed hide cannot change.

Your placed chili and your hiding selection have a dark circular chili badge with a gold rim, plus a gold outline around the chocolate. The badge keeps its contrast over every illustrated variety and stays at least 34 points wide on the 5 by 5 box. Only your own hidden chili appears before the result.

A tap selects and lifts a chocolate. Bite confirms it. The nine illustrated varieties use one deterministic assignment for both artwork and spoken names. Once per game, before biting on their turn, a person may sniff an uneaten chocolate other than their own chili. Only they learn the answer. Norwegian uses "Lukt på en".

The finishing bite swaps in the burned piece with a short shake, a haptic and the burn sound. About 0.4 seconds later, both chilis and their round owner avatars fade in. After another 0.24 seconds, the note and result actions slide up. The board keeps its size and the screen scrolls. Shared positions use the same "You both picked the same one!" headline for both people and a "Same one!" celebration. Reduce Motion shows the settled reveal. Each person sees only the note their partner wrote. The loser reads the winner's note as the note that counts. The winner reads the loser's note as what they escaped. If the partner wrote no note, no note card appears. This also applies to game-chat results and developer scenarios.

Either person may request a rematch. The previous nonstarter is the suggested chooser, but either person may choose and become the next starter. Keep the last unseen result through a rematch. Against each other shows lifetime wins. Together shows lifetime completed games. Hiding and each bite count toward the couple streak.

## Artwork and sound

The whole board pieces are `GameHubPiccanteHeart`, `GameHubPiccanteDrizzle`, `GameHubPiccanteNut`, `GameHubPiccanteGoldDrizzle`, `GameHubPiccanteWhiteTruffle`, `GameHubPiccanteRosette`, `GameHubPiccantePraline`, `GameHubPiccanteLavenderStripes` and `GameHubPiccanteFlower`. Eaten and burned tiles use `GameHubPiccanteWrapper` and `GameHubPiccanteBurned`. The chocolate PNGs have a 450-pixel longest side. `GameHubPiccanteChili` is a 96 by 88 transparent sticker, generated with the illustration skill and checked on plum at marker size. The wrapper is square, and the chocolate aspect ratios are between 0.980 and 1.009. They display at less than 150 points. The illustration skill's alpha and fringe checks pass for all eleven. The board draws only the tray and game-state overlays around those images.

The chosen second hub candidate imports at 900 by 622 pixels, aspect 1.447. Its 600-pixel canvas width puts its lower edge at 640. The warm beat sits over the front-right chocolate near 0.80 across and 0.70 down. Three separate tutorial stickers show the tucked note, the bitten chili and the sniff. All cutouts pass the illustration checker and were inspected on plum.

## Sounds

The developer picked these CC0 recordings by ear. Every file is cut from its author's original WAV at the source interval listed below. All prepared WAVs are mono 44.1 kHz signed 16-bit PCM, normalized under [the game audio standard](../game-audio.md). The source intervals below describe the selected recordings before that final loudness pass. These files are recordings, not recipes. `ios/Scripts/game-sounds.swift` writes only its synthesized recipe outputs and leaves recordings untouched.

Each confirmed bite carries a server playback time 0.9 seconds after acceptance. Both phones estimate their clock offset with a timed server request and play the crunch at that deadline. The game number and bite ordinal select the same one of five recordings at the shared event level. Bite taps give an immediate haptic but wait for confirmation before playing audio. Burn uses the event level, 0.32 seconds after the crunch, followed by the chili reveal at 0.72 seconds and the note at 0.96 seconds. These stages use absolute deadlines so local delays do not accumulate. A late update catches up immediately.

Moves older than two seconds replay locally for someone returning later. Network delivery beyond the scheduled start and unequal request latency can still cause audible differences.

Lift, successful private sniff and queued hide use the interaction level. The Same one chime uses the event level when its reveal appears. Reduce Motion skips historical replay and staged reveals, while confirmed live bites keep their scheduled crunch. Clock sampling runs independently of replay and retries after failure. Without a clock sample, bites replay locally with 0.32 seconds between them. The audio session stays ambient. The silent switch mutes game sounds. A partner's lift over this person's chili still plays only its heartbeat haptic.

Common bite processing was extraction, downmix, resampling, DC removal, second-order 40 Hz high-pass, 2 ms fade-in, 18 ms fade-out and peak normalization to -3 dBFS. No pitch shift, layering, time stretch, reverb or synthetic mouth sound was added to the bites. The rice-cake source already includes its author's mix.

### GameSoundPiccanteBite1.caf

Imported from `bites/bite-a.wav`.

- Source: https://freesound.org/people/ursenfuns/sounds/535012/
- Author: ursenfuns
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Crunchy Bite
- Download: original WAV, https://freesound.org/people/ursenfuns/sounds/535012/download/
- Edits: source interval 0.340 to 0.940 s; common bite processing listed above.

### GameSoundPiccanteBite2.caf

Imported from `bites/bite-b.wav`.

- Source: https://freesound.org/people/black_trillium/sounds/752128/
- Author: black_trillium
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Eating A Biscuit or Cookie
- Download: original WAV, https://freesound.org/people/black_trillium/sounds/752128/download/
- Edits: source interval 1.670 to 2.230 s; common bite processing listed above.

### GameSoundPiccanteBite3.caf

Imported from `bites/bite-c.wav`.

- Source: https://freesound.org/people/SammygoodTunes/sounds/844811/
- Author: SammygoodTunes
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: crunch
- Download: original WAV, https://freesound.org/people/SammygoodTunes/sounds/844811/download/
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
- Download: original WAV, https://freesound.org/people/Anthousai/sounds/398756/download/
- Edits: source interval 0.860 to 1.440 s; common bite processing listed above.

### GameSoundPiccanteBurn1.caf

Imported from `burn.wav`.

- Source page: https://freesound.org/people/bottles/sounds/382313/
- Author: bottles
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Sizzle / Acid Burn
- Download: original WAV, https://freesound.org/people/bottles/sounds/382313/download/
- Edits: Extracted source interval 0.120 to 1.320 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteLift1.caf

Imported from `lift.wav`.

- Source page: https://freesound.org/people/golovlev.sound/sounds/632220/
- Author: golovlev.sound
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: paper, thin, tracing, blueprint, rustle.wav
- Download: original WAV, https://freesound.org/people/golovlev.sound/sounds/632220/download/
- Edits: Extracted source interval 3.650 to 4.070 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteSniff1.caf

Imported from `sniff.wav`.

- Source page: https://freesound.org/people/spookymodem/sounds/202101/
- Author: spookymodem
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Sniffing.wav
- Download: original WAV, https://freesound.org/people/spookymodem/sounds/202101/download/
- Edits: Extracted source interval 1.640 to 1.870 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteHide1.caf

Imported from `hide.wav`.

- Source page: https://freesound.org/people/Mafon2/sounds/360646/
- Author: Mafon2
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Paper drawn with rustle
- Download: original WAV, https://freesound.org/people/Mafon2/sounds/360646/download/
- Edits: Extracted source interval 1.020 to 1.320 s; downmixed to mono; removed DC; 70 Hz high-pass and 5500 Hz low-pass, both second-order; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.

### GameSoundPiccanteSameOne1.caf

Imported from `same-one.wav`.

- Source page: https://freesound.org/people/Seth_Makes_Sounds/sounds/852531/
- Author: Seth_Makes_Sounds
- License: CC0 1.0 Universal.
- License URL: https://creativecommons.org/publicdomain/zero/1.0/
- Original title: Bell Sound
- Download: original WAV, https://freesound.org/people/Seth_Makes_Sounds/sounds/852531/download/
- Edits: Extracted source interval 0.000 to 0.700 s; downmixed to mono; removed DC; 70 Hz high-pass and 4800 Hz low-pass, both second-order; layered the same hit at +160 ms, resampled 1.26 times faster (a major third higher) and 1.33 times louder; 3 ms fade-in and short fade-out, longer 120 ms release for sizzles; peak-normalized to -3 dBFS; converted to 44.1 kHz signed 16-bit PCM WAV. No synthesis or reverb.
