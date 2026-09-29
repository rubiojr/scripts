#!/usr/bin/env bash
# Record a Phosh session over SSH. Requires local ssh/scp and remote wf-recorder.
set -euo pipefail

usage() {
  printf 'Usage: %s user@host [output.mkv]\n' "${0##*/}"
  printf 'SSH as the user running Phosh. Press Ctrl+C to stop and download.\n'
}

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  usage
  exit 0
fi
if (( $# < 1 || $# > 2 )) || [[ $1 == -* ]]; then
  usage >&2
  exit 2
fi

host=$1
output=${2:-"phone-recording-$(date +%Y%m%d-%H%M%S).mkv"}
# Make the destination unambiguously a local path for scp.
[[ $output == /* ]] || output="$PWD/$output"
if [[ -e $output || -L $output ]]; then
  printf 'Refusing to overwrite: %s\n' "$output" >&2
  exit 1
fi
if [[ ! -d $(dirname -- "$output") ]]; then
  printf 'Output directory does not exist: %s\n' "$output" >&2
  exit 1
fi
if [[ ! -t 0 ]]; then
  printf 'Run this script from an interactive terminal so Ctrl+C reaches the phone.\n' >&2
  exit 1
fi

# Quote one argument for the remote POSIX shell (not Bash-specific %q).
shell_quote() {
  printf "'%s'" "${1//\'/\'\\\'\'}"
}

remote_dir=$(ssh "$host" 'command -v wf-recorder >/dev/null || { echo "wf-recorder is not installed" >&2; exit 1; }; mktemp -d /tmp/pmos-record.XXXXXXXXXX')
# Only accept the expected mktemp output before interpolating it into commands.
if [[ ! $remote_dir =~ ^/tmp/pmos-record\.[a-zA-Z0-9]+$ ]]; then
  printf 'Unexpected remote temporary directory: %s\n' "$remote_dir" >&2
  exit 1
fi
remote_file="$remote_dir/recording.mkv"

# Expand these variables on the phone, not locally.
# shellcheck disable=SC2016
remote_script='
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
    [ -S "$socket" ] || continue
    export WAYLAND_DISPLAY="${socket##*/}"
    break
  done
fi
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  echo "No Wayland socket found. SSH as the user running Phosh." >&2
  exit 1
fi
printf "Recording %s; press Ctrl+C to stop.\n" "$WAYLAND_DISPLAY"
exec wf-recorder -c libx264 -p preset=ultrafast -p crf=23 -x yuv420p -f "$1"
'

printf 'Remote recording: %s:%s\n' "$host" "$remote_file"
# SSH puts the local terminal in raw mode: Ctrl+C goes to the remote PTY,
# which sends SIGINT to wf-recorder. Wait for it to finalize before copying.
# The local trap also prevents an interrupt from aborting the whole script.
trap ':' INT
status=0
ssh -tt "$host" "sh -c $(shell_quote "$remote_script") sh $(shell_quote "$remote_file")" || status=$?

# Protect the transfer from an accidental second Ctrl+C.
trap '' INT
if (( status != 0 && status != 130 )); then
  printf 'Recording SSH session exited with status %s; trying to retrieve the video.\n' "$status" >&2
fi

# Paths are intentionally expanded locally and quoted for the remote shell.
# shellcheck disable=SC2029
if ! ssh "$host" "test -s $(shell_quote "$remote_file")"; then
  printf 'No nonempty recording could be confirmed at %s:%s\n' "$host" "$remote_file" >&2
  exit 1
fi

printf '\nDownloading to %s ...\n' "$output"
if scp "$host:$remote_file" "$output"; then
  # shellcheck disable=SC2029
  if ! ssh "$host" "rm -f $(shell_quote "$remote_file") && rmdir $(shell_quote "$remote_dir")"; then
    printf 'Downloaded successfully, but remote cleanup failed: %s\n' "$remote_dir" >&2
  fi
  printf 'Saved: %s\n' "$output"
else
  printf 'Download failed. The remote recording has been kept. Retry with:\n' >&2
  printf '  scp %q %q\n' "$host:$remote_file" "$output" >&2
  exit 1
fi
