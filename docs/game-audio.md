# Game audio standard

Every bundled `GameSound` uses the same file loudness reference. `CallSound` has a louder one of its own. Playback levels describe the effect's role, so a new recording does not need a different volume number to fit the app.

## Files

- Mono CAF, 44.1 kHz signed 16-bit PCM.
- Integrated loudness of -26 LUFS for game sounds and -16 LUFS for call sounds, within 0.5 LU.
- True peak at or below -3 dBTP for game sounds and -1 dBTP for call sounds. Peak normalization alone does not meet this standard.
- Measure the entire effect with silence appended to reach 400 ms for shorter clips. This padding is measurement-only. Keep the original frame count and event timing.

`ios/Scripts/normalize-game-sounds.py` owns the numeric limits. It uses static gain when that meets the peak ceiling, otherwise an oversampled lookahead limiter. It measures the final quantized CAF again before accepting it. The script prepares every changed file before replacing originals and leaves files that already conform untouched.

Call sounds (`CallSound` in `ios/PaeoniaApp/Services/Calls/CallSound.swift`) live in `Resources/CallSounds`, one `CallSound<Name>.caf` per case with no variants. The ringback loops, so its file is one whole period, the phrase followed by silence. Their notes sit between 0.9 and 5 kHz, an octave above the game sounds, because a phone's speaker plays little below about 600 Hz. A ringback on A4 at -26 LUFS was barely audible on an iPhone held to the ear.

## Playback

`GameSound+Levels.swift` assigns every effect to one level. Its exhaustive switch makes a new sound require a deliberate assignment.

| Level | Gain | Use |
| --- | --- | --- |
| Subtle | 0.3 | Repeated ticks and pawn steps |
| Interaction | 0.5 | Taps, cards, pieces, lifts and private actions |
| Event | 0.7 | Turns, sent actions, bites, burns and results |

Call `GameSound.tap.play()` or the corresponding effect. Use `level:` only when the same sound has a different role, such as a quieter partner-step cue. `intensity:` is a relative envelope for a bounce, replay or animation, bounded to 0 through 1. Do not use it to compensate for an audio file's loudness. Variants have no random gain variation. Piccante keeps its shared variant selection and playback deadlines.

The player keeps the existing ambient audio session and silent-switch behavior. Call sounds play in the call's audio session instead, through `CallSoundPlayer`, at full gain (1.0). That is a call level of their own, above the game levels, because a call plays through the earpiece, a car or AirPods as often as through the speaker, and the ringback must be heard over the room. The app does not normalize a user's voice messages, recordings or music.

## Authoring and checks

After importing a recording, run from the repository root:

```sh
python3 ios/Scripts/normalize-game-sounds.py --write
python3 ios/Scripts/normalize-game-sounds.py --check
```

The script needs FFmpeg and FFprobe. The repository's audio CI job installs them. `ios/Scripts/game-sounds-inventory.json` lists the required variant count for every `GameSound` case. Update it when adding or removing a variant. `--check` compares the complete library against that inventory, and the call sounds against the `CallSound` cases. It refuses missing or unexpected files, unknown sound names, incorrect PCM formats, silence and out-of-range levels. `--library game` or `--library call` checks one library.

The pre-commit hook checks changed audio and audio tooling too. It exports the staged checker, inventory and audio into a temporary directory and measures those exact files. Stage the normalized replacement after running `--write`.

`ios/Scripts/game-sounds.swift ios/PaeoniaApp/Resources` writes both libraries and normalizes its own generated outputs automatically. It leaves recorded Piccante effects untouched. Each imported effect keeps its source and editing provenance in its game's document. Listen to changed effects on the same output route, and compare repeated variants, attacks and overlapping cues as well as the measurements.
