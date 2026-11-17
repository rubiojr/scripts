#!/bin/bash
# Bootstrap a Fedora host to build and test Fade/Fyne apps,
# and to drive them with Fade autopilot in a headless Wayland session.
#
# Go, staticcheck and other dev tools come from mise, not dnf. This script
# installs only system packages, plus a fade-headless helper in /usr/local/bin.
#
# Run as a regular user with sudo, or as root.

set -euo pipefail

PACKAGES=(
	# Build: cgo toolchain, make, git for go modules
	gcc make pkgconf-pkg-config git-core

	# GLFW (Fade's glfw-touch) builds both the X11 and Wayland backends
	libX11-devel libXcursor-devel libXrandr-devel libXinerama-devel
	libXi-devel libXxf86vm-devel
	wayland-devel libxkbcommon-devel
	mesa-libGL-devel mesa-libEGL-devel

	# Headless Wayland session: compositor, software GL, session bus
	weston mesa-dri-drivers dbus-daemon
)

as_root() {
	if ((EUID == 0)); then "$@"; else sudo "$@"; fi
}

echo "==> Installing system packages"
as_root dnf install -y "${PACKAGES[@]}"

echo "==> Installing /usr/local/bin/fade-headless"
helper=$(mktemp)
trap 'rm -f "$helper"' EXIT
cat >"$helper" <<'HELPER'
#!/bin/bash
# fade-headless: run a command inside a private headless Weston session.
#
#   fade-headless [--fresh] COMMAND [ARGS...]
#
# The command gets WAYLAND_DISPLAY, a private XDG_RUNTIME_DIR and its own
# D-Bus session bus. DISPLAY is unset so Fade picks Wayland.
# --fresh points XDG_CONFIG_HOME, XDG_DATA_HOME and XDG_STATE_HOME at empty
# directories so the app starts with no saved state; XDG_CACHE_HOME is kept.
# FADE_HEADLESS_SIZE sets the output size, 1280x800 by default.
#
# Weston runs with --debug, so weston-screenshooter works inside the session:
#   fade-headless sh -c './app & sleep 3; weston-screenshooter; kill $!'
set -euo pipefail

fresh=0
if [[ ${1:-} == --fresh ]]; then fresh=1; shift; fi
if (($# == 0)); then
	sed -n '2,15s/^# \{0,1\}//p' "$0" >&2
	exit 2
fi

size=${FADE_HEADLESS_SIZE:-1280x800}
dir=$(mktemp -d "${TMPDIR:-/tmp}/fade-headless.XXXXXX")
chmod 0700 "$dir"
mkdir -m 0700 "$dir/run"
socket=wayland-fade

XDG_RUNTIME_DIR=$dir/run weston --backend=headless --renderer=pixman \
	--width="${size%x*}" --height="${size#*x}" --socket="$socket" \
	--idle-time=0 --debug >"$dir/weston.log" 2>&1 &
weston_pid=$!

cleanup() {
	kill "$weston_pid" 2>/dev/null || true
	wait "$weston_pid" 2>/dev/null || true
	rm -rf "$dir"
}
trap cleanup EXIT

for _ in $(seq 100); do
	[[ -S $dir/run/$socket ]] && break
	if ! kill -0 "$weston_pid" 2>/dev/null; then
		echo "fade-headless: weston exited:" >&2
		cat "$dir/weston.log" >&2
		exit 1
	fi
	sleep 0.1
done
if [[ ! -S $dir/run/$socket ]]; then
	echo "fade-headless: weston did not start within 10s:" >&2
	cat "$dir/weston.log" >&2
	exit 1
fi

envs=(XDG_RUNTIME_DIR="$dir/run" WAYLAND_DISPLAY="$socket")
if ((fresh)); then
	mkdir -p "$dir/config" "$dir/data" "$dir/state"
	envs+=(XDG_CONFIG_HOME="$dir/config" XDG_DATA_HOME="$dir/data" XDG_STATE_HOME="$dir/state")
fi

status=0
env -u DISPLAY "${envs[@]}" dbus-run-session -- "$@" || status=$?
exit "$status"
HELPER
as_root install -m 0755 "$helper" /usr/local/bin/fade-headless

echo "==> Checking mise-managed tools"
# Under sudo or as root these resolve against root's PATH, not yours.
missing=0
for tool in go staticcheck; do
	if command -v "$tool" >/dev/null; then
		echo "    $tool: $(command -v "$tool")"
	else
		echo "    $tool: not found (as your user: mise install)"
		missing=1
	fi
done
if ((EUID == 0)) && ((missing)); then
	echo "    Running as root; mise tools are per user, so check again as your user."
fi

cat <<'EOF'

Done.

Tests (Fyne's headless driver, no compositor needed):
  make check

Autopilot (needs the autopilot build tag and FADE_AUTOPILOT):
  printf 'wait idle\ntap "Inbox"\nwait 1s\nquit\n' > demo.txt
  go build -tags autopilot,migrated_fynedo -o /tmp/myapp ./cmd/myapp
  FADE_AUTOPILOT=$PWD/demo.txt fade-headless --fresh /tmp/myapp
EOF
