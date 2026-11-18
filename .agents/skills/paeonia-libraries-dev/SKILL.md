---
name: paeonia-libraries-dev
description: Libraries.dev effects in the Paeonia iOS app. Use to add another product from the package (border beam, thinking orbs, voice glow or ring, bot avatars, metal fx), to play or retune a distortion wave, to update the pinned Libraries.dev commit, or to verify one of its effects.
---

# Libraries.dev in Paeonia

Libraries.dev (`https://github.com/Jakubantalik/Libraries.dev`, by Jakub Antalik) is one repository of SwiftUI effects drawn with Metal shaders. Paeonia links it as one Swift package and uses three products from it: `DistortionWavesKit`, for the wave that rises from Send on the Us tab's drawing screen, `ThinkingOrbsKit`, for the ring of dots around the partner on Mind Meld's waiting screen, and `VoiceGlowKit`, for the glow on the chat composer's recording bar. Most effects from it are **shader effects**: SwiftUI views passed through `.layerEffect` or `.colorEffect`. That fact drives most rules below. `ThinkingOrbsKit` is the exception. It draws with `Canvas` in a `TimelineView`, so the shader rules and the Metal toolchain don't apply to it.

## The package

- **Products.** The root `Package.swift` lists them: `BorderBeamKit`, `ThinkingOrbsKit`, `VoiceGlowKit`, `BotAvatarsKit`, `MetalFxKit`, `MagnetKit`, `VoiceRingKit`, `VoiceRingEmotion`, `VoicePositionKit`, `DistortionWavesKit`. Their floor is iOS 17.
- **Source and docs.** Xcode's checkout is `~/Library/Developer/Xcode/DerivedData/Paeonia-*/SourcePackages/checkouts/Libraries.dev/`. Each port has a README at `packages/<name>/ports/ios/<Kit>/README.md`, next to its Swift and `.metal` files. The site has one page per effect, such as `https://libraries.dev/waves.html`. Read the README and the Swift source before you design with an effect. They say what each side, option and callback does.
- **Licences.** The code is MIT. The ML model files (`Magnet.mfxl`, `VoicePosition.mfxl` and the voice emotion models) are under `LICENSE-MODEL.md`, which allows them only in personal or non-commercial apps unless the developer has a Pro or Business plan. Paeonia is paid, so ask the developer before you ship any model file.
- **The pin.** The project's `XCRemoteSwiftPackageReference "Libraries.dev"` is `2A2D0B022FE7000000A7BE1A` and follows branch `main`, like the Chat package. `Package.resolved` pins the commit. The repo's semver tags predate its Swift manifest, so stay on the branch.

## Adding a product

1. Read the port's README and source. Note any side or content it takes that could hold a UIKit-backed view, any model file it loads, and how it starts and ends.
2. Link the product to the PaeoniaApp target only. In `ios/Paeonia.xcodeproj/project.pbxproj`, add a `PBXBuildFile` and an `XCSwiftPackageProductDependency` whose `package` is `2A2D0B022FE7000000A7BE1A`. List the build file in the app's Frameworks phase (`000000000000000130000000`) and the dependency in the target's `packageProductDependencies`. Copy the `DistortionWavesKit` entries, and grep for the next free ID in the `2A2D0B..2FE7000000A7BE1A` series. `Package.resolved` does not change, because the package is already pinned.
3. Build with `./scripts/xcode-build-agent.sh`. Until the first build resolves the product, `scripts/app-typecheck` reports `no such module`.
4. Add the product's file to `docs/implementation-map.md` and to "In the app" below.

## Updating the pin

1. Read what changed upstream for the ports in use: `gh api 'repos/Jakubantalik/Libraries.dev/commits?path=packages/distortion-waves'`.
2. Move the revision in `Package.resolved`, and build.
3. If `ios/Scripts/collect-package-licences.py` exists, run it and commit `PackageLicences.txt`. `scripts/check-repo-rules.mjs` fails while that list and the pins differ.
4. Record every effect in use again (see Verifying), because tuned values can look different on a new commit.

## Shader rules

- **UIKit drops out.** SwiftUI cannot pass UIKit-backed views or materials through a shader, so they vanish from the effect. That covers every `UIViewRepresentable` (the PencilKit canvas, MapLibre, camera and video previews, the crop view), the navigation and tab bars, and `.material` or glass backgrounds. Give an effect plain SwiftUI with an opaque background, or a picture of the screen from `PaeoniaAppWindow.snapshot(of:)`.
- **Mounted copies.** A kit can mount the views you give it several times. `DistortionWave` keeps three copies of each side plus a hidden warm-up stage. A view that owns a view model, `.task` work, a live connection or a PencilKit canvas would run that many times, so pass a picture or a static view.
- **Metal toolchain.** Xcode compiles the `.metal` files with a toolchain it downloads separately, per Xcode version. The wrappers build with the Xcode that `scripts/lib/paeonia-xcode.sh` selects (Xcode 27.3 beta 2 on 2026-11-18), not the default one. When it is missing, `xcode-build-agent.sh` says so and names that Xcode. Ask the developer before downloading it. CI's `ios.yml` downloads it before building. `swift build` and `scripts/swift-typecheck` never compile shaders, so check an effect only through the Xcode wrappers.
- **First run.** A kit compiles its shaders the first time it draws. On the simulator the first send after launch waited about 0.35 s before the wave moved. Apple's `Shader.compile(as:)` would prewarm it, but the shaders sit in the kit's bundle, so that needs a change upstream.

## Distortion waves

- **Playing one.** Call `@Environment(\.screenWave)` with the frame the wave starts from, in global coordinates, and a `DistortionWaveStyle`. `PaeoniaScreenWaveHost` (`ios/PaeoniaApp/Shared/DesignSystem/Components/PaeoniaScreenWave.swift`) sits once on the app's root and once in `DeveloperScenarioHost`, like the petal shower. It pictures the whole window, bars included, and runs the wave over the picture. It skips the wave under Reduce Motion and VoiceOver, blocks every touch while the wave plays, ends it on a window resize or a second after its duration if the kit's `onFinish` never comes, fades the picture out, and sets `cornerRadius` to the window's measured corners. Callers only pick the style.
- **Why the root host.** A council of three models chose it on 2026-11-18, after the developer rejected a wave that stopped under the navigation bar. A wave inside a screen stops at the bars. An overlay on a `NavigationStack` misses the tab bar. A window of its own has no guaranteed order against the call overlay's window, which sits at `.normal + 1`. A `fullScreenCover` sets `PaeoniaAppWindow.isCovered`, which the presence pill and chat slide-over read. Hiding the bar resizes the drawing canvas, which rescales the drawing.
- **Where to call it.** Call it from the state that means the action began, not from the tap. The drawing screen calls it from `.onChange(of: viewModel.delivery)` on `.sending`, which `save()` sets only once the drawing can go, so a drawing too big to send shows its error without a wave over it. Call it from screens on the app's root only. A sheet draws above the root, so a wave from one would play under it. Skip flows that move on as soon as the action finishes, such as the onboarding drawing steps, because the picture would still show the old step.
- **Haptics.** The host plays the wave's haptic in the same `onAppear` that starts the animation, timed from the style: a soft buzz that tightens over `anticipation` while the screen falls toward the source, 60 ms of silence, a full-strength thump and crack at the launch, and a buzz that fades over `travel * 0.4` as the swell goes out (`ScreenWaveHaptics` in `PaeoniaScreenWave.swift`, played through `PaeoniaHapticPattern`). `screenWave(...)` returns `true` when a wave played. The caller then plays no haptic of its own for that action, because a haptic that comes from the network finishing lands after the wave and feels detached from it. The drawing screen skips `drawingSaved` and `drawingSent` after a wave this way. Any new effect's haptic follows the same rule: start it with the animation and time it from the style's numbers. Make the release the strongest moment. A build-up above about half strength, or one that runs right up to the release tap, masks the tap, and the developer felt that as anticlimactic. So keep the build-up near half, end it just before the release, and hit the release at full strength. Haptics only play on a device, so the developer judges the feel on their iPhone.
- **Styles.** Keep a feature's tuned style as a static `DistortionWaveStyle` in the feature, as `widgetDrawingSend` is in `WidgetDrawingSendWave.swift` (`.vertical`, `.sunset`). Types are `.vertical` (up from a wide button at the bottom), `.horizontal` (across from a tall source at the left) and `.center` (a ring from an avatar, tuned for a 500 pt sheet). Palettes are `.colorful`, `.green`, `.ocean`, `.sunset`, `.mono` and `.single(color)`.
- **Length.** The whole app ignores touches until the wave ends, so keep a style near 2 to 2.5 s. Its length is `anticipation + max(travel * 0.6, linger + rimFade, linger + hairlineLinger + hairlineFade, particleLife)`. The kit's `.vertical` default is 3.6 s, and `widgetDrawingSend` shortens `rimFade` to 1.8, `hairlineFade` to 1.6 and `particleLife` to 1.8 for about 2.3 s.
- **Writing a host or a new kind of overlay.** These cost a recording each on 2026-11-18:
  - `onGeometryChange` placed after `.ignoresSafeArea` reports the frame before the expansion, so measure inside it.
  - `DistortionWave` animates when `isRevealed` changes. Mount it at `false`, then flip it in `onAppear`.
  - `UIWindow.effectiveRadius(corner:)` returns 0. A view that fills the window with `.containerConcentric()` corners returns the screen's radius, 62 pt on an iPhone 17 Pro.

## Thinking orbs

- **Look.** The kit draws grey dots, white on `.dark` and black on `.light`. Pass `theme: .dark` and add `.colorMultiply(.paeoniaAccentPrimary)` to tint them, so the color is the same in both appearances. `displaySize` scales the drawing without blurring it. Render all nine states headless on the Mac with the kit's `snapshot.sh`, run on a copy of the port in the scratchpad, to choose one.
- **VoiceOver.** The kit labels each orb in English ("Thinking…"), so hide it with `.accessibilityHidden(true)` and let the text next to it speak.
- **Reduce Motion.** The kit draws one still frame, so the caller needs no branch.

## In the app

- `DistortionWavesKit`: `PaeoniaScreenWave.swift` (the host) and `WidgetDrawingSendWave.swift` (the drawing screen's style).
- `ThinkingOrbsKit`: `MindMeldWaitingView.swift` (the `.breathing` ring around the partner's portrait while they are in the game).
- `VoiceGlowKit`: `ThreadChatComposer+Voice.swift`, the recording bar. It is an overlay drawn over its content, not a shader over it, so the bar's glass stays. Drive it with `levelProvider: recorder.liveLevel`, never the kit's `VoiceMeter`: the meter runs its own audio engine and sets its own audio session category, which would fight `DailyVoiceAudioSession` (ducking, never pausing music) and the `AVAudioRecorder` that records the take. `liveLevel` applies the meter's gain of 15.5 to the recorder's RMS, so the glow reacts as the kit tunes it. The kit's emotion detection and live transcript are VoiceGlow Pro and are not used. On the simulator the Mac's microphone feeds the recorder, so `say` during a take shows the glow rise.

## Verifying

Record every effect you add or retune on the simulator, and check smoothness on the developer's iPhone. [verification.md](verification.md) has the recipe: the scenario, the taps that get ink on the canvas, how to read the report, and the on-device hitch trace.
