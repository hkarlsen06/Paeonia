# App Store Connect

Paeonia uses the same ASC CLI workflow as Tidex. `config.json` pins the CLI version and identifies the app. Metadata and screenshot commands show a read-only plan by default. Add `--apply` when an upload is authorized.

## Setup

The Mac already has ASC 6.5.3 installed. On another machine, install the matching binary from the [ASC releases](https://github.com/rorkai/App-Store-Connect-CLI/releases) and verify its release checksums. `ASC_BIN` can select an executable outside `PATH`. Check a CLI upgrade against the commands below before changing `cliVersion`.

The ignored `ios/app-store/.env` symlink points to `/Users/hkarlsen06/Documents/Privat/Utviklernøkler/Secrets/Paeonia/asc.env`. It contains `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_PRIVATE_KEY_PATH`. Environment variables override the file. The wrapper gives ASC a temporary key copy with mode 0600 and removes it afterward. Keep credentials outside Git. Recreate this symlink in a fresh checkout, or supply the three environment variables.

## Metadata

Run from the repository root:

```sh
bun run --cwd ios generate-metadata:source-only
bun run app-store:validate
bun run app-store metadata
bun run app-store metadata --apply
```

`ios/Scripts/appstore-metadata-source.json` remains the source for English, British English keywords and Norwegian. The generator writes `metadata/app-info/<locale>.json` and `metadata/version/<version>/<locale>.json`. The version comes from `ios/Version.xcconfig`. A new version inherits the latest earlier version's translated fields and URLs. Generation preserves fields it does not manage, including support, marketing and privacy URLs.

Ordinary metadata uploads leave review information unchanged. The separate `review-metadata` command reads `metadata/review-information.json` and manages only `notes`, so remote contact details and demo credentials stay unchanged. It rejects the unresolved `{{REVIEW_CODES}}` template marker before calling ASC. Refresh the reviewer codes with `bun run review-codes:mint` before a requested review upload, and copy its completed notes into this JSON file. The template in `ios/Scripts/app-review-notes.txt` explains the review journey.

Use `bun run app-store review-metadata` to plan only promotional text and review notes, and add `--apply` to upload them. Copyright lives in `config.json`.

## Screenshots

Capture and render the artwork with the existing screenshot scripts. Each locale has six iPhone and six iPad images in `ios/ASConnectScreenshots/<version>/3d/<locale>/`. The uploader stages only `iPhone-*.png` or `iPad-*.png`, checks opaque RGB PNGs and dimensions, and plans all selected sets before uploading any.

```sh
bun run app-store screenshots
bun run app-store screenshots --device iphone --locales en-US,no
bun run app-store screenshots --device ipad --replace --apply
```

Uploads skip existing matching images by default. `--replace` replaces only the selected device families and languages. Other sets stay unchanged. Uploads across several sets are not atomic. Keep partial receipts if a command fails and inspect them before retrying.

`--version 1.0.0` selects an explicit version. `--assets-dir <path>` selects an existing artwork directory. Neither option generates images or creates a remote version.

## App previews

The finished app preview films are in `ios/ASConnectScreenshots/<version>/app-preview/<locale>/paeonia-showcase-<locale>.mp4`, one for `en-US` and one for `no`. Git ignores that folder, like the screenshots, so the files exist only on the Mac that rendered them. [video/README.md](../../video/README.md) says how to render them again, and the screen recordings they need are in `ios/ASConnectScreenshots/<version>/raw/<locale>/`.

No command uploads a preview. Add each film by hand in App Store Connect, under the version's iPhone previews for its language. Each film is 886 x 1920 and 29.5 s, in H.264 with AAC sound, which App Store Connect accepts for every iPhone size. Set the poster frame to 5.0 s, where the question holds under its headline. The frame at 2.0 s is also a clean hold.

## Native commands and verification

`bun run asc <command>` uses the pinned CLI and the same credentials. This direct entry point permits writes. For read-only diagnostics, put the global flag first, as in `bun run asc --read-only apps list --bundle-id no.paeonia.app`.

The upload helpers never upload a binary, submit for review or release the app. They require an editable version when applying changes. Continue using the repository's Xcode wrappers for builds and tests.

```sh
node --test scripts/test-app-store.mjs
bun run app-store:validate
```
