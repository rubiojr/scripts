#!/bin/sh
# pw-diag.sh — collect PipeWire audio diagnostics on postmarketOS.
# Run as your normal user WHILE music is playing (and stuttering).
#   sh pw-diag.sh            # 10 s sample
#   sh pw-diag.sh 20         # 20 s sample
# Produces: pw-diag-<ts>/summary.txt (paste this) and pw-diag-<ts>.tar.gz (full data).

SAMPLE=${1:-10}
TS=$(date +%Y%m%d-%H%M%S)
OUT="$PWD/pw-diag-$TS"
mkdir -p "$OUT" || exit 1
S="$OUT/summary.txt"

have() { command -v "$1" >/dev/null 2>&1; }
sec()  { printf '\n===== %s =====\n' "$*" >>"$S"; }
run()  { printf '$ %s\n' "$*" >>"$S"; sh -c "$*" >>"$S" 2>&1; }

echo "Collecting for ${SAMPLE}s — keep the audio playing..."

# ---------- system ----------
sec "system"
run "cat /proc/device-tree/model 2>/dev/null; echo"
run "uname -a"
run "grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release"
run "ps -o comm= -p 1 2>/dev/null || cat /proc/1/comm"
run "nproc; cat /proc/loadavg"
if have apk; then run "apk list -I 2>/dev/null | grep -E 'pipewire|wireplumber|alsa-(lib|ucm)|rtkit|linux-' "; fi
run "pipewire --version 2>/dev/null | tail -n 2"
run "wireplumber --version 2>/dev/null | tail -n 2"

# ---------- audio processes ----------
sec "audio processes"
# pidof matches by executable, and pipewire-pulse is the pipewire binary, so
# identify each process by its comm and skip duplicates.
PIDS=""
for pid in $(pidof pipewire pipewire-pulse wireplumber rtkit-daemon 2>/dev/null | tr ' ' '\n' | sort -un); do
	PIDS="$PIDS $pid"
	printf '%s pid=%s\n' "$(cat "/proc/$pid/comm" 2>/dev/null)" "$pid" >>"$S"
	grep -iE 'rtprio|nice|rttime' "/proc/$pid/limits" >>"$S" 2>/dev/null
done
[ -z "$PIDS" ] && echo "!! no pipewire processes found" >>"$S"

# ---------- CPU sampling (per thread, with scheduling policy) ----------
CLK=$(getconf CLK_TCK 2>/dev/null || echo 100)
snap() { # prints: tid ticks policy rtprio comm
	for pid in $PIDS; do
		for t in /proc/"$pid"/task/*; do
			[ -r "$t/stat" ] || continue
			comm=$(cat "$t/comm" 2>/dev/null)
			# strip "pid (comm) " so fields are stable even if comm has spaces
			sed 's/^.*) //' "$t/stat" | awk -v tid="${t##*/}" -v c="$pid:$comm" \
				'{print tid, $12+$13, $39, $38, c}'
		done
	done
}
snap >"$OUT/cpu-before.txt"

# ---------- live sampling (runs during the same window) ----------
if have pw-top; then
	pw-top -b -n "$SAMPLE" >"$OUT/pw-top.txt" 2>&1 &
	PWTOP=$!
fi
: >"$OUT/cpufreq.txt"
i=0
while [ "$i" -lt "$SAMPLE" ]; do
	{
		printf 't=%s ' "$i"
		for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq; do
			[ -r "$f" ] && printf '%s ' "$(cat "$f")"
		done
		echo
	} >>"$OUT/cpufreq.txt"
	sleep 1
	i=$((i + 1))
done
[ -n "$PWTOP" ] && wait "$PWTOP" 2>/dev/null
snap >"$OUT/cpu-after.txt"

sec "thread CPU over ${SAMPLE}s (policy: 0=OTHER 1=FIFO 2=RR)"
printf '%-8s %6s %6s %6s  %s\n' TID CPU% POLICY RTPRIO PROC:THREAD >>"$S"
awk -v clk="$CLK" -v s="$SAMPLE" '
	NR==FNR { b[$1]=$2; next }
	($1 in b) { d=($2-b[$1])/clk/s*100; if (d>0.05 || $3>0)
		printf "%-8s %6.1f %6s %6s  %s\n", $1, d, $3, $4, $5 }
' "$OUT/cpu-before.txt" "$OUT/cpu-after.txt" | sort -k2 -rn >>"$S"

sec "pw-top (last 2 iterations)"
if [ -s "$OUT/pw-top.txt" ]; then
	# each iteration starts with the S ID QUANT header
	awk '/QUANT/{n++} {buf[n]=buf[n] $0 "\n"} END{for(i=(n>1?n-1:1);i<=n;i++) printf "%s", buf[i]}' \
		"$OUT/pw-top.txt" >>"$S"
else
	echo "pw-top unavailable or produced no output" >>"$S"
fi

sec "CPU governor / freq samples (kHz)"
run "for c in /sys/devices/system/cpu/cpufreq/policy*; do echo \$c: \$(cat \$c/scaling_governor) min=\$(cat \$c/scaling_min_freq) max=\$(cat \$c/scaling_max_freq) cpus=\$(cat \$c/related_cpus); done"
cat "$OUT/cpufreq.txt" >>"$S"

sec "thermal"
run "for z in /sys/class/thermal/thermal_zone*; do printf '%s %s\n' \$(cat \$z/type) \$(cat \$z/temp); done 2>/dev/null | sort -k2 -rn | head -n 8"

# ---------- PipeWire graph state ----------
sec "settings metadata"
run "pw-metadata -n settings 2>/dev/null"
sec "wpctl status"
run "wpctl status 2>/dev/null"
sec "wpctl inspect default sink"
run "wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null"
have pw-dump && pw-dump >"$OUT/pw-dump.json" 2>/dev/null

# ---------- ALSA ----------
sec "ALSA cards / running streams"
run "cat /proc/asound/cards"
for f in /proc/asound/card*/pcm*p/sub*/hw_params /proc/asound/card*/pcm*p/sub*/sw_params \
         /proc/asound/card*/pcm*p/sub*/status; do
	[ -r "$f" ] || continue
	grep -q closed "$f" 2>/dev/null && continue
	printf -- '-- %s\n' "$f" >>"$S"; cat "$f" >>"$S"
done
have aplay && aplay -l >"$OUT/aplay-l.txt" 2>&1

# ---------- config ----------
sec "config files (user + /etc; /usr/share drop-ins listed)"
for d in "$HOME/.config/pipewire" "$HOME/.config/wireplumber" /etc/pipewire /etc/wireplumber; do
	[ -d "$d" ] || continue
	find "$d" -type f | while read -r f; do
		printf -- '-- %s\n' "$f" >>"$S"; cat "$f" >>"$S"
	done
done
for d in /usr/share/pipewire /usr/share/wireplumber; do
	[ -d "$d" ] && find "$d" -path '*.conf.d/*' -type f >>"$S"
done
mkdir -p "$OUT/share-conf.d"
find /usr/share/pipewire /usr/share/wireplumber -path '*.conf.d/*' -type f 2>/dev/null |
	while read -r f; do
		cp "$f" "$OUT/share-conf.d/$(echo "$f" | tr / _)" 2>/dev/null
	done

# ---------- logs ----------
sec "logs (xrun / error lines, last 15 min)"
if have journalctl; then
	journalctl --user -u pipewire -u pipewire-pulse -u wireplumber --since "-15min" --no-pager \
		>"$OUT/journal.txt" 2>&1
fi
have logread && logread 2>/dev/null | grep -iE 'pipewire|wireplumber|spa\.' >"$OUT/logread.txt"
cat "$OUT"/journal.txt "$OUT"/logread.txt 2>/dev/null \
	| grep -iE 'xrun|underrun|resync|error|fail|warn|timeout' | tail -n 60 >>"$S"
dmesg 2>/dev/null | grep -iE 'q6|apm|gpr|apr|snd|audio|wcd|lpass|xrun|soundwire|swr' \
	| tail -n 60 >"$OUT/dmesg-audio.txt"
sec "dmesg (audio, tail)"
if [ -s "$OUT/dmesg-audio.txt" ]; then tail -n 30 "$OUT/dmesg-audio.txt" >>"$S"
else echo "(empty — dmesg may need root: sudo dmesg | grep -iE 'q6|snd|audio')" >>"$S"; fi

tar -czf "$OUT.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
echo
echo "Done."
echo "  Paste this:   $S  ($(wc -l <"$S") lines)"
echo "  Full bundle:  $OUT.tar.gz"
echo "Note: output includes app/stream names (e.g. song titles) and hostname — skim before sharing."
