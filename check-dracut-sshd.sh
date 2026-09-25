#!/usr/bin/env bash
# Inspect dracut-sshd on the running kernel; optionally repair and rebuild.
# Usage: sudo ./check-dracut-sshd.sh [--fix] [path-to-initramfs]

set -u

# Retain an absolute path for rechecking after dracut finishes. A bare script
# name (for example, "bash check-dracut-sshd.sh") is not necessarily on PATH.
self=${BASH_SOURCE[0]}
if [[ $self != */* ]]; then
    self=$(command -v "$self") || self=$PWD/${BASH_SOURCE[0]}
fi
[[ $self == /* ]] || self=$PWD/$self

usage() { printf 'Usage: %s [--fix] [path-to-initramfs]\n' "$0" >&2; exit 2; }
fix=0
image=
for arg in "$@"; do
    case $arg in
        --fix) (( fix == 0 )) || usage; fix=1 ;;
        -*) usage ;;
        *) [[ -z $image ]] || usage; image=$arg ;;
    esac
done

if (( fix )); then
    if (( EUID != 0 )); then printf '%s\n' '--fix requires root (use sudo)' >&2; exit 2; fi
    if [[ ! -r /dev/tty ]]; then printf '%s\n' '--fix requires an interactive terminal' >&2; exit 2; fi
fi

failures=0
warnings=0
ok()   { printf 'OK: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
warn() { printf 'WARN: %s\n' "$*"; warnings=$((warnings + 1)); }
result() { printf 'Result: %d failure(s), %d warning(s)\n' "$failures" "$warnings"; }

# Always read from the terminal, never from a redirected stdin. Default is no.
confirm() {
    local answer
    printf '%s [y/N] ' "$1" > /dev/tty
    IFS= read -r answer < /dev/tty || return 1
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

show_command() {
    printf '  ' > /dev/tty
    printf '%q ' "$@" > /dev/tty
    printf '\n' > /dev/tty
}

package_install() {
    local package=$1
    local -a cmd
    if command -v dnf >/dev/null 2>&1; then cmd=(dnf install "$package")
    elif command -v apt-get >/dev/null 2>&1; then cmd=(apt-get install "$package")
    elif command -v zypper >/dev/null 2>&1; then cmd=(zypper install "$package")
    elif command -v pacman >/dev/null 2>&1; then cmd=(pacman -S "$package")
    else warn "no supported package manager found; install $package manually"; return 1
    fi
    show_command "${cmd[@]}"
    confirm "Run this command?" && "${cmd[@]}"
}

module=/usr/lib/dracut/modules.d/46sshd/module-setup.sh
module_missing=0
if [[ -f $module ]]; then ok "dracut module installed ($module)"
else fail "dracut module missing ($module)"; module_missing=1
fi

lsinitrd_missing=0
if ! command -v lsinitrd >/dev/null 2>&1; then
    fail 'lsinitrd is unavailable (install dracut)'
    lsinitrd_missing=1
fi

kernel=$(uname -r)
if [[ -z $image ]]; then
    for candidate in "/boot/initramfs-$kernel.img" "/boot/initrd.img-$kernel" "/boot/initrd-$kernel"; do
        if [[ -f $candidate ]]; then image=$candidate; break; fi
    done
    # Use dracut's standard output location when building a missing image.
    [[ -n $image ]] || image="/boot/initramfs-$kernel.img"
fi

host_key_in_image=0
network_modules=0
network_config=0
locked_root=0
modules=
paths=$'\n'
if [[ ! -f $image ]]; then
    fail "initramfs not found ($image)"
elif (( ! lsinitrd_missing )); then
    printf 'Checking %s\n' "$image"
    if ! listing=$(lsinitrd "$image" 2>/dev/null); then
        fail 'cannot read initramfs with lsinitrd'
    else
        # lsinitrd prints ls -l entries; strip symlink targets before parsing.
        while IFS= read -r line; do
            [[ $line =~ ^[-dlcbps] ]] || continue
            line=${line%% -> *}
            path=${line##* }
            path=${path#./}
            paths+="$path"$'\n'
        done <<< "$listing"

        has_path() { [[ $paths == *$'\n'"$1"$'\n'* ]]; }

        if modules=$(lsinitrd -m "$image" 2>/dev/null); then
            if [[ $modules =~ (^|[[:space:]])sshd([[:space:]]|$) ]]; then
                ok 'sshd dracut module is in the image'
            else fail 'sshd dracut module is not in the image'; fi
        else warn 'could not read dracut module list from the image'; fi

        if has_path usr/sbin/sshd || has_path sbin/sshd; then
            ok 'sshd executable is in the image'
        else fail 'sshd executable is missing from the image'; fi

        if has_path root/.ssh/authorized_keys; then
            ok 'root authorized_keys is in the image'
        else fail 'root authorized_keys is missing from the image'; fi

        for kind in ed25519 ecdsa rsa dsa; do
            if has_path "etc/ssh/ssh_host_${kind}_key"; then host_key_in_image=1; fi
        done
        if (( host_key_in_image )); then ok 'SSH host private key is in the image'
        else fail 'SSH host private key is missing from the image'; fi

        if has_path usr/lib/systemd/system/sshd.service || has_path lib/systemd/system/sshd.service || has_path etc/systemd/system/sshd.service; then
            ok 'sshd.service is in the image'
        else fail 'sshd.service is missing from the image'; fi
        if has_path etc/systemd/system/sysinit.target.wants/sshd.service; then
            ok 'sshd.service is enabled in the image'
        else fail 'sshd.service is not enabled in the image'; fi
        if has_path etc/ssh/sshd_config; then ok 'sshd_config is in the image'
        else fail 'sshd_config is missing from the image'; fi

        if [[ $modules =~ (^|[[:space:]])(systemd-networkd|network|network-manager|ifcfg)([[:space:]]|$) ]]; then
            network_modules=1
            ok 'early-boot networking module is in the image'
        else warn 'no known early-boot networking module found'; fi

        while IFS= read -r path; do
            case $path in
                etc/systemd/network/*.network|etc/cmdline.d/*.conf|etc/NetworkManager/system-connections/*)
                    network_config=1 ;;
            esac
        done <<< "$paths"
        if (( network_config )); then ok 'early-boot network configuration is in the image'
        else warn 'no network config found in image; bootloader parameters may provide it'; fi

        if has_path etc/shadow; then
            shadow=$(lsinitrd -f /etc/shadow "$image" 2>/dev/null) || shadow=
            root_line=
            while IFS= read -r line; do
                if [[ $line == root:* ]]; then root_line=$line; break; fi
            done <<< "$shadow"
            if [[ $root_line == root:!* ]]; then
                fail 'initramfs root account is locked with ! (blocks public-key login)'
                locked_root=1
            elif [[ $root_line == root:* ]]; then ok 'root shadow entry allows public-key login'
            else warn 'could not inspect root shadow entry in the image'; fi
        else warn 'no /etc/shadow in image; root account behavior depends on NSS'; fi
    fi
fi
if (( EUID != 0 )); then warn 'run as root to inspect private initramfs images reliably'; fi
result

if (( ! fix )); then
    if (( failures )); then exit 1; fi
    if (( warnings )); then exit 2; fi
    exit 0
fi

printf '\nGuided repairs (each change requires confirmation):\n'
changed=0
if (( lsinitrd_missing )); then
    printf 'Install dracut for lsinitrd and image rebuilding:\n'
    if package_install dracut; then changed=1; fi
fi
if (( module_missing )); then
    printf 'Install the dracut-sshd module:\n'
    if package_install dracut-sshd; then changed=1; fi
fi
if ! command -v sshd >/dev/null 2>&1 && [[ ! -x /usr/sbin/sshd ]]; then
    printf 'Install the SSH server for the initramfs:\n'
    if package_install openssh-server; then changed=1; fi
fi

# dracut selects the first existing authorized_keys file in this order.
keyfile=
for candidate in /root/.ssh/dracut_authorized_keys /etc/dracut-sshd/authorized_keys /root/.ssh/authorized_keys; do
    if [[ -e $candidate ]]; then keyfile=$candidate; break; fi
done
if [[ -z $keyfile || ! -s $keyfile || ! -r $keyfile ]]; then
    printf 'No usable dracut root authorized_keys found (%s).\n' "${keyfile:-none}"
    if confirm 'Select a public-key file to install?'; then
        printf 'Path to public-key file: ' > /dev/tty
        IFS= read -r source < /dev/tty || source=
        if [[ -n $source && -f $source && -s $source && -r $source ]]; then
            target=${keyfile:-/etc/dracut-sshd/authorized_keys}
            show_command install -d -m 700 "${target%/*}"
            show_command install -m 600 "$source" "$target"
            if confirm "Run these commands? (replaces $target if present)"; then
                if install -d -m 700 "${target%/*}" && install -m 600 "$source" "$target"; then
                    changed=1
                else warn 'could not install authorized_keys'; fi
            fi
        else warn 'source public-key file is missing, empty, or unreadable'; fi
    fi
fi

host_key_found=0
prefix=
for candidate in /etc/ssh/dracut_ssh_host_*_key; do
    if [[ -f $candidate ]]; then prefix=dracut_; break; fi
done
for kind in ed25519 ecdsa rsa dsa; do
    if [[ -s /etc/ssh/${prefix}ssh_host_${kind}_key && -f /etc/ssh/${prefix}ssh_host_${kind}_key.pub ]]; then
        host_key_found=1
    fi
done
if (( ! host_key_found )) && [[ $prefix == dracut_ ]]; then
    warn 'dracut_ SSH host keys take precedence, but no complete pair exists; repair /etc/ssh/dracut_ssh_host_*_key{,.pub} manually'
elif (( ! host_key_found )); then
    printf 'No usable SSH host key pair found. Generate missing system host keys:\n'
    show_command ssh-keygen -A
    if confirm 'Run this command?'; then
        if command -v ssh-keygen >/dev/null 2>&1 && ssh-keygen -A; then changed=1
        else warn 'host key generation failed'; fi
    fi
fi

if (( locked_root )); then
    root_hash=
    while IFS=: read -r account hash rest; do
        if [[ $account == root ]]; then root_hash=$hash; break; fi
    done < /etc/shadow
    if [[ $root_hash == '!'* ]]; then
        warn 'changing root to * removes its password; public-key login can still work'
        show_command usermod -p '*' root
        if confirm "Run this command to replace root's !-locked password?"; then
            if usermod -p '*' root; then changed=1; else warn 'root account update failed'; fi
        fi
    else
        warn 'host root is not !-locked; rebuilding may fix the stale image'
    fi
fi

if (( ! network_modules || ! network_config )); then
    netconf=/etc/dracut.conf.d/91-dracut-sshd-dhcp.conf
    if [[ -e $netconf ]]; then
        warn "$netconf already exists; inspect it manually rather than overwrite it"
    else
        printf 'Optional early-boot DHCP setup (skip if bootloader/networkd already configures networking):\n'
        show_command install -d -m 755 /etc/dracut.conf.d
        printf "  printf '%%s\\\\n' 'add_dracutmodules+=\" network \"' 'kernel_cmdline+=\" rd.neednet=1 ip=dhcp \"' > %q\n" "$netconf" > /dev/tty
        if confirm 'Run these commands?'; then
            if install -d -m 755 /etc/dracut.conf.d && printf '%s\n' 'add_dracutmodules+=" network "' 'kernel_cmdline+=" rd.neednet=1 ip=dhcp "' > "$netconf"; then
                changed=1
                ok "wrote $netconf"
            else warn 'could not write dracut network configuration'; fi
        fi
    fi
fi

if (( failures || changed )); then
    if command -v dracut >/dev/null 2>&1; then
        printf 'Rebuild initramfs for running kernel %s:\n' "$kernel"
        show_command dracut -f "$image" "$kernel"
    fi
    if command -v dracut >/dev/null 2>&1 && confirm 'Run this command?'; then
        if dracut -f "$image" "$kernel"; then
            printf '\nRechecking the rebuilt image:\n'
            exec bash "$self" "$image"
        fi
        fail 'dracut rebuild failed'
    fi
fi
printf '\nRepairs complete; rerun this checker after addressing any remaining findings.\n'
if (( failures )); then exit 1; fi
if (( warnings )); then exit 2; fi
exit 0
