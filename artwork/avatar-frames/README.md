# Avatar frame sources

`original-four-blender/sources/paeonia-frames-final.blend` is the authoritative editable scene for Peony, Ribbon, Moon and Candy Twist. Earlier scenes, Blender backups, construction and rendering scripts, original exports and measured geometry are preserved here.

`first-nine-generated` and `remaining-ten-generated` contain the 19 generated raster originals, prompts, provenance, measured geometry and import/analysis scripts. These frames have no Blender meshes. Historical paths in scripts and provenance refer to the original working folders. Review and adjust those paths before rerunning scripts.

The current app outputs live in `ios/PaeoniaApp/Resources/Assets.xcassets/AvatarFrames`. Placement metadata lives in the app's `AvatarDecoration.swift`. Original Blender exports predate later placement adjustments.

`SHA256SUMS.json` records the SHA-256 of each copied original and helper. Every copy was verified against the durable source archive at `/Users/hkarlsen06/Documents/Paeonia/Avatar frames`. That archive also retains process screenshots and verification evidence, which are not app sources.
