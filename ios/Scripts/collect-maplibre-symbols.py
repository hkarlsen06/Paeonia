#!/usr/bin/env python3
"""Include the pinned MapLibre device symbols in iOS archives."""

import os
from pathlib import Path
import re
import shutil
import subprocess


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

    products = Path(os.environ["BUILT_PRODUCTS_DIR"])
    framework = products / "MapLibre.framework/MapLibre"
    symbols = products / "MapLibre_ios_device.framework.dSYM"
    dwarf = symbols / "Contents/Resources/DWARF/MapLibre_ios_device"
    expected = uuids(framework)
    if not expected <= uuids(dwarf):
        raise RuntimeError(f"Bundled MapLibre symbols do not match framework UUIDs {expected}")

    destination = Path(os.environ["DWARF_DSYM_FOLDER_PATH"]) / symbols.name
    if destination.resolve() != symbols.resolve():
        if destination.exists():
            shutil.rmtree(destination)
        shutil.copytree(symbols, destination)
    print(f"Bundled MapLibre symbols included: {sorted(expected)}")


if __name__ == "__main__":
    try:
        collect()
    except (OSError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"error: Could not collect MapLibre archive symbols: {error}")
