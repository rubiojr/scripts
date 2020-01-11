#!/bin/bash
set -e
set -x

apt update
apt install --yes vim build-essential curl wget openssh-client procps sudo lsof less
adduser --disabled-password rubiojr --gecos foo || true
mkdir -p /home/rubiojr/tmp; cd /home/rubiojr/tmp
tar -xzvf ../go-textile_v0.7.7_linux-amd64.tar.gz
./install
rm -rf /home/rubiojr/tmp/*

su -l -c "textile daemon" rubiojr
#tail -f /dev/null
