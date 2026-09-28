#!/usr/bin/env bash
# Fetch the latest Ladybird Flatpak built by CI on master and install/upgrade it.
# Requires: gh (authenticated: `gh auth login`) and flatpak.
set -euo pipefail

REPO="LadybirdBrowser/ladybird"
WORKFLOW="flatpak.yml"
BRANCH="master"
APP_ID="org.ladybird.Ladybird"
ARCH="${ARCH:-$(uname -m)}"   # x86_64 or aarch64
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/ladybird-flatpak/installed-sha"
FORCE="${FORCE:-0}"

for cmd in gh flatpak; do
  command -v "$cmd" >/dev/null || { echo "error: $cmd not found" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "error: run 'gh auth login' first (artifact downloads need auth)" >&2; exit 1; }

# Latest successful push build on master that still has an unexpired artifact for our arch.
echo ":: Looking for the latest successful $WORKFLOW run on $BRANCH ($ARCH)..."
run_id="" sha="" artifact=""
while read -r id head; do
  name=$(gh api "repos/$REPO/actions/runs/$id/artifacts" \
    --jq ".artifacts[] | select(.expired == false and (.name | contains(\"$ARCH\"))) | .name" | head -n1)
  if [[ -n "$name" ]]; then
    run_id=$id sha=$head artifact=$name
    break
  fi
done < <(gh run list -R "$REPO" -w "$WORKFLOW" -b "$BRANCH" -e push -s success -L 10 \
           --json databaseId,headSha --jq '.[] | "\(.databaseId) \(.headSha)"')

[[ -n "$run_id" ]] || { echo "error: no usable artifact found in recent runs" >&2; exit 1; }
echo ":: Run $run_id, commit ${sha:0:12}, artifact '$artifact'"

if [[ "$FORCE" != 1 && -f "$STATE_FILE" && "$(cat "$STATE_FILE")" == "$sha" ]] \
   && flatpak info --user "$APP_ID" >/dev/null 2>&1; then
  echo ":: Already up to date (${sha:0:12}). Set FORCE=1 to reinstall."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo ":: Downloading..."
gh run download "$run_id" -R "$REPO" -n "$artifact" -D "$tmp"
bundle=$(find "$tmp" -name '*.flatpak' -print -quit)
[[ -n "$bundle" ]] || { echo "error: no .flatpak file in artifact" >&2; exit 1; }

# Runtime (org.kde.Platform) comes from Flathub.
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

echo ":: Installing $bundle..."
flatpak install --user --noninteractive --reinstall "$bundle"

mkdir -p "$(dirname "$STATE_FILE")"
echo "$sha" > "$STATE_FILE"
echo ":: Done. Run with: flatpak run $APP_ID"
