#!/bin/bash
# Safe to run many times
set -e

if [ `whoami` != 'root' ]; then
  echo "Run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# apt-get update only if the cache is not fresh enough
pkg_cache_mod=$(($(date +%s) - $(stat --printf="%Y" /var/cache/apt/pkgcache.bin)))
if [ ! -f /var/cache/apt/pkgcache.bin ] || [ $pkg_cache_mod -gt 43200 ]; then
  apt-get update
fi

# Sources
if [ "$(lsb_release -s -i)" = "Debian"]; then
  codename=$(lsb_release -c -s)
  cat > /etc/apt/sources.list << EOF
deb http://http.debian.net/debian jessie main contrib non-free
deb http://http.debian.net/debian/ jessie-updates main contrib non-free
deb http://ftp.debian.org/debian jessie-backports main
deb http://security.debian.org/ jessie/updates main contrib non-free
EOF
fi

# apt-get install -y sysdig sysdig-dkms debootstrap devscripts iperf

apt-get install -y git rsync vim htop nmap telnet sysstat iotop nicstat mtr-tiny curl wget tinc openvpn dnsutils unattended-upgrades

# Enable unnatended upgrades
dpkg-reconfigure -plow unattended-upgrades

# Causes trouble frequently
sed -i 's/\(^AcceptEnv LANG LC_\*\)/#\1/' /etc/ssh/sshd_config
service ssh restart

# optional
# wavemon

# Tinc service unit
# curl "http://tinc-vpn.org/git/browse?p=tinc;a=blob_plain;f=systemd/tinc@.service;hb=refs/heads/1.1" -o /etc/systemd/system/tinc@.service

if [ ! -f /usr/local/bin/speedtest ]; then
  curl https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest_cli.py > /usr/local/bin/speedtest
fi
chmod +x /usr/local/bin/speedtest
