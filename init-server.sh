#!/bin/bash
set -e

if [ `whoami` != 'root' ]; then
  echo "This script requires root."
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: init-server <user>"
  exit 1
fi
user="$1"

export DEBIAN_FRONTEND=noninteractive

apt update
apt-get install -y vim unattended-upgrades curl tcpdump sudo
apt full-upgrade
apt-get autoremove -y --purge

adduser --disabled-password $user --gecos foo || true

su -c "mkdir -p ~/.ssh" $user
chmod 0700 /home/$user/.ssh
chown -R $user:$user /home/$user/.ssh
su -c "curl -s https://github.com/$user.keys > /home/$user/.ssh/authorized_keys" $user

echo "Etc/UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata

grep $user /etc/sudoers || echo "$user ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers
