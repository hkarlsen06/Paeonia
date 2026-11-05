#!/usr/bin/env bash
# Custom Siri tools require SDK 27.3. Select it for this process only.
paeonia_find_developer_dir() {
  local candidate version major minor
  local candidates=()
  if [ -n "${DEVELOPER_DIR:-}" ]; then
    candidates=("$DEVELOPER_DIR")
  else
    candidates=("$(xcode-select -p 2>/dev/null)" /Applications/Xcode*.app/Contents/Developer)
  fi
  for candidate in "${candidates[@]}"; do
    [ -d "$candidate" ] || continue
    version="$(DEVELOPER_DIR="$candidate" xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)" || continue
    IFS=. read -r major minor _ <<< "$version"
    if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] \
      && (( major > 27 || (major == 27 && minor >= 3) )); then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  echo "Paeonia requires Xcode with iOS SDK 27.3 or newer. Install it in /Applications or set DEVELOPER_DIR to its Contents/Developer directory." >&2
  return 1
}

PAEONIA_SELECTED_DEVELOPER_DIR="$(paeonia_find_developer_dir)" || return 1
export DEVELOPER_DIR="$PAEONIA_SELECTED_DEVELOPER_DIR"
unset PAEONIA_SELECTED_DEVELOPER_DIR
unset -f paeonia_find_developer_dir
