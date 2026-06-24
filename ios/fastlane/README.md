fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Generate App Store metadata files and upload them

### ios generate_metadata

```sh
[bundle exec] fastlane ios generate_metadata
```

Generate App Store metadata files without uploading

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload existing App Store metadata files without regenerating

### ios validate_metadata

```sh
[bundle exec] fastlane ios validate_metadata
```

Validate App Store metadata source and generated files

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
