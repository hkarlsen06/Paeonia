#!/usr/bin/env python3
"""Include the pinned MapLibre device symbols in iOS archives."""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zipfile


def uuids(binary):
    output = subprocess.check_output(
        ["xcrun", "dwarfdump", "--uuid", str(binary)], text=True
    )
    values = set(re.findall(r"UUID: ([0-9A-Fa-f-]+) \(([^)]+)\)", output))
    if not values:
        raise RuntimeError(f"No debug identifiers found in {binary}")
    return values


def collect():
    if os.environ.get("ACTION") != "install" or os.environ.get("PLATFORM_NAME") != "iphoneos":
        print("MapLibre symbols: skipped outside an iOS archive.")
        return

    source = Path(os.environ["SRCROOT"])
    resolved = source / "Paeonia.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    pins = json.loads(resolved.read_text())["pins"]
    pin = next(p for p in pins if p["identity"] == "maplibre-gl-native-distribution")
    version = pin["state"]["version"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise RuntimeError(f"Unsupported MapLibre release version: {version}")

    framework = Path(os.environ["BUILT_PRODUCTS_DIR"]) / "MapLibre.framework/MapLibre"
    expected = uuids(framework)
    cache = Path(os.environ["DERIVED_FILE_DIR"]) / "MapLibre-symbols" / version
    symbols = cache / "MapLibre.framework.dSYM"
    dwarf = Path("Contents/Resources/DWARF/MapLibre")

    if not (symbols / dwarf).is_file() or not expected <= uuids(symbols / dwarf):
        cache.mkdir(parents=True, exist_ok=True)
        url = (
            "https://github.com/maplibre/maplibre-native/releases/download/"
            f"ios-v{version}/MapLibre_ios_device.framework.dSYM.zip"
        )
        print(f"Downloading MapLibre {version} device symbols...", flush=True)
        with tempfile.TemporaryDirectory(dir=cache) as temporary:
            temporary = Path(temporary)
            archive = temporary / "symbols.zip"
            subprocess.run(
                ["curl", "--fail", "--location", "--silent", "--show-error",
                 "--retry", "3", "--connect-timeout", "30", "--max-time", "300",
                 "--output", str(archive), url], check=True
            )
            extracted = temporary / "extracted"
            with zipfile.ZipFile(archive) as zipped:
                for name in zipped.namelist():
                    path = Path(name)
                    if path.is_absolute() or ".." in path.parts:
                        raise RuntimeError(f"Unsafe symbol archive entry: {name}")
                zipped.extractall(extracted)
            candidates = list(extracted.rglob("*.dSYM/Contents/Resources/DWARF/*"))
            matches = [p for p in candidates if expected <= uuids(p)]
            if len(matches) != 1:
                raise RuntimeError(f"MapLibre {version} symbols do not match framework UUIDs {expected}")
            if symbols.exists():
                shutil.rmtree(symbols)
            shutil.copytree(matches[0].parents[3], symbols)
            (symbols / dwarf.parent / matches[0].name).rename(symbols / dwarf)

    destination = Path(os.environ["DWARF_DSYM_FOLDER_PATH"]) / symbols.name
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(symbols, destination)
    print(f"MapLibre {version} symbols included: {sorted(expected)}")


if __name__ == "__main__":
    try:
        collect()
    except (OSError, ValueError, KeyError, StopIteration, RuntimeError,
            subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        raise SystemExit(f"error: Could not collect MapLibre archive symbols: {error}")
