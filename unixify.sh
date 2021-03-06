#!/bin/bash
# Safe to run many times
#
# TODO
# adduser --disabled-login --disabled-password  --gecos '' <username>
# su -c "mkdir /home/<username>/.ssh && chmod 700 ~/.ssh" <username>
# su -c "curl -L https://github.com/rubiojr.keys > /home/<username>/.ssh/authorized_keys" <username>
#
set -e

cleanup(){
  rm -rf $workdir
}

if [ `whoami` != 'root' ]; then
  echo "Run as root." >&2
  exit 1
fi


export DEBIAN_FRONTEND=noninteractive
workdir=$(mktemp -d)
cd $workdir

trap cleanup EXIT

# Update sources
old_sources=$(md5sum /etc/apt/sources.list | cut -f1 -d ' ' 2>/dev/null)
if [ "$(lsb_release -s -i)" = "Debian" ]; then
  codename=$(lsb_release -c -s)
  cat > /etc/apt/sources.list << EOF
deb http://http.debian.net/debian jessie main contrib non-free
deb http://http.debian.net/debian/ jessie-updates main contrib non-free
deb http://ftp.debian.org/debian jessie-backports main
deb http://security.debian.org/ jessie/updates main contrib non-free
EOF
fi

# apt-get update only if the cache is not fresh enough
pkg_cache_mod=$(($(date +%s) - $(stat --printf="%Y" /var/cache/apt/pkgcache.bin)))
if [ ! -f /var/cache/apt/pkgcache.bin ] || [ $pkg_cache_mod -gt 43200 ] || [ "$old_sources" != "$(md5sum /etc/apt/sources.list | cut -f1 -d ' ' 2>/dev/null)" ]; then
  apt-get -qq update
fi

# apt-get install -y sysdig sysdig-dkms debootstrap devscripts iperf

apt-get install -qq -y git rsync vim htop nmap telnet sysstat iotop nicstat mtr-tiny curl wget tinc openvpn dnsutils unattended-upgrades ssh-import-id sudo dnsmasq

# Vim is now the default editor
update-alternatives --set editor /usr/bin/vim.basic

# Enable unnatended upgrades
cat > /etc/apt/apt.conf.d/02periodic << EOF
// Control parameters for cron jobs by /etc/cron.daily/apt //
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Verbose "0";
EOF

# Causes trouble frequently
sed -i 's/\(^AcceptEnv LANG LC_\*\)/#\1/' /etc/ssh/sshd_config
service ssh restart

# optional
# wavemon

# Tinc service unit
# curl "http://tinc-vpn.org/git/browse?p=tinc;a=blob_plain;f=systemd/tinc@.service;hb=refs/heads/1.1" -o /etc/systemd/system/tinc@.service

if [ ! -f /usr/local/bin/speedtest ]; then
  curl -s https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest_cli.py > /usr/local/bin/speedtest
fi
chmod +x /usr/local/bin/speedtest
