#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>" >&2
  echo "Example: $0 1.1.5" >&2
  exit 2
fi

version="$1"
tag="v$version"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid semantic version: $version" >&2
  exit 1
fi

required_paths=(
  CHANGELOG.md
  Info.plist
  Makefile
  Sources/UpdateManager.swift
  .github/workflows/release.yml
  .github/workflows/dev-release.yml
  .github/workflows/pages.yml
  .github/scripts/changelog-section.sh
  .github/scripts/hydrate-website-release.mjs
)
for path in "${required_paths[@]}"; do
  if [[ ! -f "$path" ]]; then
    echo "Missing required release file: $path" >&2
    exit 1
  fi
done

megaphone_remote=""
while IFS= read -r remote; do
  url="$(git remote get-url "$remote" 2>/dev/null || true)"
  if [[ "$url" == *"Kuberwastaken/megaphone"* ]]; then
    megaphone_remote="$remote"
    break
  fi
done < <(git remote)

if [[ -z "$megaphone_remote" ]]; then
  echo "No git remote points to Kuberwastaken/megaphone." >&2
  exit 1
fi

plist_value() {
  local key="$1"
  awk -v key="$key" '
    index($0, "<key>" key "</key>") { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }
  ' Info.plist
}

bundle_name="$(plist_value CFBundleName)"
bundle_id="$(plist_value CFBundleIdentifier)"
short_version="$(plist_value CFBundleShortVersionString)"
build_version="$(plist_value CFBundleVersion)"

[[ "$bundle_name" == "Megaphone" ]] || { echo "Unexpected bundle name: $bundle_name" >&2; exit 1; }
[[ "$bundle_id" == "com.kuberwastaken.megaphone" ]] || { echo "Unexpected bundle identifier: $bundle_id" >&2; exit 1; }
[[ "$short_version" == "$version" ]] || { echo "CFBundleShortVersionString is $short_version, expected $version" >&2; exit 1; }
[[ "$build_version" == "$version" ]] || { echo "CFBundleVersion is $build_version, expected $version" >&2; exit 1; }

if git rev-parse "$tag" >/dev/null 2>&1; then
  echo "Tag already exists locally: $tag" >&2
  exit 1
fi

set +e
git ls-remote --exit-code --tags "$megaphone_remote" "refs/tags/$tag" >/dev/null 2>&1
ls_remote_status=$?
set -e

if [[ $ls_remote_status -eq 0 ]]; then
  echo "Tag already exists on $megaphone_remote: $tag" >&2
  exit 1
elif [[ $ls_remote_status -eq 2 ]]; then
  :
else
  echo "git ls-remote failed while checking origin tag $tag" >&2
  exit "$ls_remote_status"
fi

if ! grep -q 'tags:' .github/workflows/release.yml || ! grep -q 'v\*\.\*\.\*' .github/workflows/release.yml; then
  echo "Release workflow does not appear to be semver tag-triggered." >&2
  exit 1
fi

notes_file="$(mktemp "${TMPDIR:-/tmp}/megaphone-release-notes.XXXXXX")"
trap 'rm -f "$notes_file"' EXIT

if ! .github/scripts/changelog-section.sh "$version" >"$notes_file"; then
  echo "Could not extract CHANGELOG.md section for $version" >&2
  exit 1
fi

if [[ ! -s "$notes_file" ]]; then
  echo "Extracted changelog section is empty for $version" >&2
  exit 1
fi

if ! grep -q "^## \\[$version\\]" "$notes_file"; then
  echo "Extracted changelog section has an unexpected heading." >&2
  exit 1
fi

grep -q 'Megaphone.dmg' .github/workflows/release.yml \
  || { echo "Stable workflow does not publish Megaphone.dmg." >&2; exit 1; }
grep -q 'Megaphone-Dev.dmg' .github/workflows/dev-release.yml \
  || { echo "Dev workflow does not publish Megaphone-Dev.dmg." >&2; exit 1; }
grep -q 'Kuberwastaken/megaphone/releases' Sources/UpdateManager.swift \
  || { echo "Updater is not pointed at Megaphone GitHub releases." >&2; exit 1; }
grep -q 'api.github.com/repos/Kuberwastaken/megaphone/releases' .github/scripts/hydrate-website-release.mjs \
  || { echo "Website hydration is not pointed at Megaphone releases." >&2; exit 1; }
grep -q 'updates.json' .github/scripts/hydrate-website-release.mjs \
  || { echo "Website hydration does not publish the updater manifest." >&2; exit 1; }
grep -q 'gh workflow run pages.yml' .github/workflows/release.yml \
  || { echo "Stable release does not refresh the website." >&2; exit 1; }

previous_tag="$(git tag --merged HEAD --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | head -1)"
if [[ -z "$previous_tag" ]]; then
  echo "No previous stable semver tag is reachable from HEAD." >&2
  exit 1
fi

echo "Release checks passed for $tag"
echo "Megaphone remote: $megaphone_remote"
echo "Previous reachable release: $previous_tag"
echo
cat "$notes_file"
