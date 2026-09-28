#!/bin/sh
# Rootless podman setup for Nura.
# Run as the regular user (not root); uses sudo where needed.
set -eu

USER_NAME=$(id -un)
if [ "$USER_NAME" = "root" ]; then
	echo "Run this as your regular user, not root." >&2
	exit 1
fi

echo "==> Installing packages"
sudo apk add podman fuse-overlayfs shadow-uidmap podman-compose podman-docker

echo "==> Configuring subuid/subgid for $USER_NAME"
for f in /etc/subuid /etc/subgid; do
	sudo touch "$f"
	if ! grep -q "^$USER_NAME:" "$f"; then
		echo "$USER_NAME:100000:65536" | sudo tee -a "$f" >/dev/null
	fi
done

echo "==> Checking /dev/fuse"
if [ ! -e /dev/fuse ]; then
	sudo modprobe fuse
fi

echo "==> Writing ~/.config/containers/storage.conf (fuse-overlayfs)"
mkdir -p "$HOME/.config/containers"
cat >"$HOME/.config/containers/storage.conf" <<'EOF'
[storage]
driver = "overlay"

[storage.options.overlay]
mount_program = "/usr/bin/fuse-overlayfs"
EOF

# Storage created before the config above uses native overlay and won't work.
if ! podman info >/dev/null 2>&1; then
	echo "==> Resetting broken container storage"
	rm -rf "$HOME/.local/share/containers/storage" "$HOME/.local/share/containers/cache"
fi
podman system migrate

echo "==> Enabling linger so user containers can run without a login session"
sudo loginctl enable-linger "$USER_NAME"

echo "==> Testing"
podman info | grep -iA3 graphDriver
podman run --rm docker.io/library/alpine echo "podman works"
