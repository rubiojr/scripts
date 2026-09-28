#!/bin/sh
# pw-tune.sh — PipeWire fixes/tuning for postmarketOS on the Fairphone (Gen. 6).
# Idempotent: re-running only touches what differs; services restart only on change.
#
# Run as your normal user (doas/sudo is used for /etc when needed):
#   sh pw-tune.sh              # apply
#   sh pw-tune.sh --dry-run    # show what would change
#   sh pw-tune.sh --aec        # also install the (fixed) echo-cancel config if missing
#   sh pw-tune.sh --remove-aec # remove the echo-cancel config
#   sh pw-tune.sh --no-restart # write files only
#
# Tunables (env), both off by default:
#   HEADROOM=1024        add an ALSA headroom rule (only if stutter returns)
#   RESAMPLE_QUALITY=2   cheaper 44.1->48 kHz resampling (PipeWire default is 4)

set -u

SPEAKER=${SPEAKER:-alsa_output.platform-sound.HiFi__Speaker__sink}
MIC=${MIC:-alsa_input.platform-sound.HiFi__Mic__source}
HEADROOM=${HEADROOM:-0}
RESAMPLE_QUALITY=${RESAMPLE_QUALITY:-}
PW_ETC=${PW_ETC:-/etc/pipewire}
CFG=${XDG_CONFIG_HOME:-$HOME/.config}
BACKUP_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/pw-tune/backup

DRY=0 AEC=auto RESTART=1 CHANGED=0
for a in "$@"; do
	case $a in
	--dry-run | -n) DRY=1 ;;
	--aec) AEC=install ;;
	--remove-aec) AEC=remove ;;
	--no-restart) RESTART=0 ;;
	-h | --help) sed -n '2,15p' "$0"; exit 0 ;;
	*) echo "unknown option: $a" >&2; exit 2 ;;
	esac
done

if [ "$(id -u)" = 0 ]; then
	echo "Run as your normal user, not root (user config lives in \$HOME)." >&2
	exit 1
fi

log() { printf '%s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

as_root() {
	if [ -w "$PW_ETC" ] || { [ ! -e "$PW_ETC" ] && [ -w "$(dirname "$PW_ETC")" ]; }; then "$@"
	elif have doas; then doas "$@"
	elif have sudo; then sudo "$@"
	else echo "need root for $PW_ETC but no doas/sudo" >&2; exit 1; fi
}

TMP=$(mktemp) || exit 1
trap 'rm -f "$TMP"' EXIT

# put_file DEST [root]  — content on stdin; writes only if different.
put_file() {
	dest=$1 root=${2:-}
	cat >"$TMP"
	if [ -f "$dest" ] && cmp -s "$TMP" "$dest"; then
		log "  ok       $dest"
		return
	fi
	CHANGED=1
	if [ "$DRY" = 1 ]; then
		log "  change   $dest"
		if [ -f "$dest" ]; then diff -u "$dest" "$TMP" | sed 's/^/    /'; else sed 's/^/    + /' "$TMP"; fi
		return
	fi
	if [ -f "$dest" ]; then backup "$dest"; fi
	if [ -n "$root" ]; then
		as_root mkdir -p "$(dirname "$dest")" && as_root cp "$TMP" "$dest" && as_root chmod 644 "$dest"
	else
		mkdir -p "$(dirname "$dest")" && cp "$TMP" "$dest"
	fi || { echo "failed to write $dest" >&2; exit 1; }
	log "  wrote    $dest"
}

# Keep the first-seen version of any file we replace or remove.
backup() {
	b="$BACKUP_DIR$1"
	[ -e "$b" ] && return
	mkdir -p "$(dirname "$b")" && cp "$1" "$b" && log "  backup   $1 -> $b"
}

# rm_file DEST [root]
rm_file() {
	dest=$1 root=${2:-}
	[ -e "$dest" ] || { log "  ok       $dest (absent)"; return; }
	CHANGED=1
	if [ "$DRY" = 1 ]; then log "  remove   $dest"; return; fi
	backup "$dest"
	if [ -n "$root" ]; then as_root rm -f "$dest"; else rm -f "$dest"; fi && log "  removed  $dest"
}

# ---------------------------------------------------------------------------
log "== ALSA headroom (Qualcomm DSP reports position in coarse steps)"
HEADROOM_CONF=$CFG/wireplumber/wireplumber.conf.d/50-alsa-headroom.conf
if [ "$HEADROOM" -gt 0 ] 2>/dev/null; then
	put_file "$HEADROOM_CONF" <<EOF
# Managed by pw-tune.sh
monitor.alsa.rules = [
  {
    matches = [ { node.name = "~alsa_output.*" } ]
    actions = {
      update-props = {
        api.alsa.headroom    = $HEADROOM
        api.alsa.period-size = 1024
      }
    }
  }
]
EOF
else
	rm_file "$HEADROOM_CONF"
fi

log "== Resampling quality (${RESAMPLE_QUALITY:-PipeWire default})"
for f in "$CFG/pipewire/client.conf.d/50-resample.conf" \
         "$CFG/pipewire/pipewire-pulse.conf.d/50-resample.conf"; do
	if [ -z "$RESAMPLE_QUALITY" ]; then
		rm_file "$f"
		continue
	fi
	put_file "$f" <<EOF
# Managed by pw-tune.sh
stream.properties = {
    resample.quality = $RESAMPLE_QUALITY
}
EOF
done

log "== Echo cancellation ($PW_ETC/pipewire.conf.d/50-echo-cancel.conf)"
AEC_CONF=$PW_ETC/pipewire.conf.d/50-echo-cancel.conf
[ "$AEC" = auto ] && { if [ -e "$AEC_CONF" ]; then AEC=install; else AEC=skip; fi; }
case $AEC in
skip) log "  skip     not present (use --aec to install)" ;;
remove) rm_file "$AEC_CONF" root ;;
install)
	put_file "$AEC_CONF" root <<EOF
# Managed by pw-tune.sh
# Acoustic echo cancellation for VoLTE speakerphone calls.
# ec_sink/ec_source are NOT meant to be the defaults: point call audio at them
# (target.object) or switch defaults only for the duration of a call. When
# nothing uses them, the passive capture/playback let the mic and AEC suspend.
# Targets must match real node names (wpctl status -n); dont-fallback stops
# WirePlumber rerouting them into the role loopbacks if a name is missing.
context.modules = [
    {   name = libpipewire-module-echo-cancel
        args = {
            library.name = aec/libspa-aec-webrtc
            source.props = {
                node.name = "ec_source"
                node.description = "Echo-cancelled microphone"
            }
            sink.props = {
                node.name = "ec_sink"
                node.description = "Echo-cancelled speakers"
            }
            capture.props = {
                node.name = "ec_capture"
                target.object = "$MIC"
                node.passive = true
                node.dont-fallback = true
            }
            playback.props = {
                node.name = "ec_playback"
                target.object = "$SPEAKER"
                node.passive = true
                node.dont-fallback = true
                media.role = "Loopback"
            }
        }
    }
]
EOF
	;;
esac

# ---------------------------------------------------------------------------
if [ "$DRY" = 1 ]; then
	log "== dry run: $([ "$CHANGED" = 1 ] && echo 'changes pending' || echo 'nothing to change')"
	exit 0
fi

if [ "$RESTART" = 0 ]; then
	log "== --no-restart: skipping service restart and default-device check"
	exit 0
fi

if [ "$CHANGED" = 1 ]; then
	log "== Restarting PipeWire"
	if systemctl --user is-active -q pipewire 2>/dev/null; then
		systemctl --user restart pipewire pipewire-pulse wireplumber
	else
		log "  systemd --user not managing pipewire; log out and back in to apply"
		exit 0
	fi
fi

# Wait for WirePlumber to publish the default metadata.
i=0
until pw-metadata -n default 2>/dev/null | grep -q "key:'default\."; do
	i=$((i + 1)); [ "$i" -ge 15 ] && { log "  WirePlumber not ready; skipping default-device check"; exit 0; }
	sleep 1
done

node_exists() { pw-cli ls Node 2>/dev/null | grep -q "node.name = \"$1\""; }

log "== Default devices (echo-cancel nodes should not be the defaults)"
# fix_default KEY BAD_NODE GOOD_NODE
fix_default() {
	if ! pw-metadata -n default 0 "$1" 2>/dev/null | grep -q "\"$2\""; then
		log "  ok       $1"
		return
	fi
	if ! node_exists "$3"; then
		log "  WARN     $1 is $2 but $3 not found; left unchanged"
		return
	fi
	pw-metadata -n default 0 "$1" "{ \"name\": \"$3\" }" Spa:String:JSON >/dev/null &&
		log "  set      $1 -> $3"
}
fix_default default.configured.audio.sink ec_sink "$SPEAKER"
fix_default default.configured.audio.source ec_source "$MIC"

if [ -e "$AEC_CONF" ]; then
	for n in "$SPEAKER" "$MIC"; do
		node_exists "$n" || log "  WARN     AEC target $n not found (check: wpctl status -n)"
	done
fi

log "== Done. Verify during playback with: pw-top"
log "   The output device should be a driver line (no leading '+'), and the mic should be S (suspended)."
