#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
# Update apt catalog and upgrade installed packages
apt-get update -q
apt-get -y -q full-upgrade
apt install -y vim secure-delete htop nmap iotop sysstat tcpdump traceroute curl

curl -s https://github.com/rubiojr.keys > /root/.ssh/authorized_keys

# Install packages
apt-get -q -y install git-core unattended-upgrades htop iotop vim

# Install sysstat, then configure if this is a new install.
sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
/etc/init.d/sysstat restart

apt autoremove --purge --yes
