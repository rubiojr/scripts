#!/bin/bash
set -e

if [ `whoami` != 'root' ]; then
  echo "Run as root." >&2
  exit 1
fi

apt-get update
apt-get install -y git vim htop nmap telnet sysstat iotop bonnie++ nicstat sysdig sysdig-dkms mtr-tiny curl wget debootstrap devscripts tinc openvpn dnsutils iperf

# optional
# wavemon

# Tinc service unit
# curl "http://tinc-vpn.org/git/browse?p=tinc;a=blob_plain;f=systemd/tinc@.service;hb=refs/heads/1.1" -o /etc/systemd/system/tinc@.service

if [ ! -f /usr/local/bin/speedtest ]; then
  curl https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest_cli.py > /usr/local/bin/speedtest
fi
chmod +x /usr/local/bin/speedtest
