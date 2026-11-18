#!/usr/bin/env python3
"""Collects the licence files of the app's Swift packages into the text file that the More tab
shows under Licences.

    ios/Scripts/collect-package-licences.py

Run it after a package is added, removed or updated, and commit the file it writes
(ios/PaeoniaApp/Resources/Licences/PackageLicences.txt). `scripts/check-repo-rules.mjs` fails
while that file names other packages or versions than Package.resolved.

It reads the pins in Package.resolved and takes each package's licence files from Xcode's checkout
of that package, so this worktree needs one earlier build. A package that ships a prebuilt
framework can carry another licence inside it, as WebRTC does, so the downloaded frameworks are
read too. It stops when a package has no checkout or no licence file, so no package is left out of
the list without anyone noticing.

In the file, a form feed on its own line starts each package after the first. A package's first
line is its name and version, the second is where it comes from, and the licence follows a blank
line. `PackageLicence.parse` in the app reads the same format.
"""
import glob
import json
import os
import plistlib
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
PROJECT = os.path.join(ROOT, "ios", "Paeonia.xcodeproj")
RESOLVED = os.path.join(PROJECT, "project.xcworkspace", "xcshareddata", "swiftpm", "Package.resolved")
OUTPUT = os.path.join(ROOT, "ios", "PaeoniaApp", "Resources", "Licences", "PackageLicences.txt")
LICENCE_FILE = re.compile(r"^(licen[sc]e|copying|notice)(\.|$)", re.IGNORECASE)
SEPARATOR = "\f"


def stop(message):
    sys.exit(f"collect-package-licences: {message}")


def checkouts():
    """The folder where Xcode cloned this worktree's packages."""
    for record in glob.glob(os.path.expanduser("~/Library/Developer/Xcode/DerivedData/*/info.plist")):
        try:
            with open(record, "rb") as stream:
                workspace = plistlib.load(stream).get("WorkspacePath", "")
        except (OSError, ValueError):
            continue
        folder = os.path.join(os.path.dirname(record), "SourcePackages", "checkouts")
        if os.path.realpath(workspace) == os.path.realpath(PROJECT) and os.path.isdir(folder):
            return folder
    stop("Xcode has not built this worktree yet. Run ./scripts/xcode-build-agent.sh first.")


def licence_files(folder, depth):
    """The licence files in `folder` and up to `depth` folders below it, nearest first."""
    found = []
    for level in range(depth + 1):
        pattern = os.path.join(glob.escape(folder), *["*"] * level, "*")
        found += sorted(
            path for path in glob.glob(pattern)
            if os.path.isfile(path) and LICENCE_FILE.match(os.path.basename(path))
        )
    return found


def package(pin, folder):
    """One package's entry: its name and version, its source, and its licences."""
    location = pin["location"]
    name = location.rstrip("/").rsplit("/", 1)[-1].removesuffix(".git")
    checkout = os.path.join(folder, name)
    if not os.path.isdir(checkout):
        stop(f"{name} has no checkout in {folder}. Build the app again and rerun.")
    files = licence_files(checkout, 0)
    if not files:
        stop(f"{name} has no licence file in {checkout}. Find its licence and add it by hand.")
    # A downloaded framework sits in artifacts/<package>/<target>/<name>.xcframework.
    files += licence_files(os.path.join(os.path.dirname(folder), "artifacts", name), 2)
    texts = []
    for path in files:
        with open(path, encoding="utf-8") as stream:
            text = stream.read().replace(SEPARATOR, "").strip()
        if text not in texts:
            texts.append(text)
    state = pin["state"]
    version = state.get("version") or state["revision"][:12]
    return f"{name} {version}\n{location.removesuffix('.git')}\n\n" + "\n\n".join(texts)


def main():
    with open(RESOLVED, encoding="utf-8") as stream:
        pins = json.load(stream)["pins"]
    folder = checkouts()
    entries = sorted((package(pin, folder) for pin in pins), key=str.lower)
    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", encoding="utf-8") as stream:
        stream.write(f"\n{SEPARATOR}\n".join(entries) + "\n")
    print(f"Wrote {len(entries)} packages to {os.path.relpath(OUTPUT, ROOT)}")


if __name__ == "__main__":
    main()
