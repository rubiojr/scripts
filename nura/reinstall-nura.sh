#!/bin/sh
# Reinstall the saved /etc/apk/world package set on a fresh postmarketOS install.
# Run as the regular user; uses sudo.
set -eu

PACKAGES="
btop
bubblewrap
build-base
coreutils
fuse-overlayfs
git
git-lfs
htop
mise
rsync
tailscale
vim
"

sudo apk update

# apk add is all-or-nothing: one unknown package aborts the whole install.
# Try everything at once, then fall back to one at a time to find the culprits.
# shellcheck disable=SC2086
if sudo apk add $PACKAGES; then
	echo "==> All packages installed"
	exit 0
fi

echo "==> Bulk install failed, retrying one by one"
failed=""
for p in $PACKAGES; do
	if ! sudo apk add "$p" >/dev/null 2>&1; then
		failed="$failed $p"
	fi
done

if [ -n "$failed" ]; then
	echo "==> Failed to install:$failed" >&2
	exit 1
fi
echo "==> All packages installed"
