#!/bin/bash
# Fire and forget tor relay setup
#
# Alternatives out there:
# * https://github.com/micahflee/tor-relay-bootstrap/blob/master/bootstrap.sh
#
set -e

if [ `whoami` != 'root' ]; then
  echo "This script requires root."
  exit 1
fi

apt-key list | grep -q 886DDD89 || {
  gpg --keyserver keys.gnupg.net --recv 886DDD89
  gpg --export A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89 | apt-key add -
}

cat > /etc/apt/sources.list.d/tor.list <<EOF
deb     http://deb.torproject.org/torproject.org $(lsb_release -c -s) main
EOF

cat > /etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu precise main universe multiverse
deb http://archive.ubuntu.com/ubuntu precise-updates main universe multiverse
deb http://security.ubuntu.com/ubuntu precise-security main universe multiverse
EOF

apt-get update
apt-get install -y unattended-upgrades ntp

# Optional firewall setup, doesn't work in some VPS servers
# apt-get install -y ufw
# ufw allow 9001
# ufw allow 22
# ufw --force enable

/etc/init.d/ntp stop || true

echo "Etc/UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
ntpdate pool.ntp.org

service cron restart
service rsyslog restart
service ntp start

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

apt-get install -y deb.torproject.org-keyring tor tor-geoipdb
# tor-arm package deps broken on precise last time I checked
# apt-get install -y tor-arm
service tor stop

cat > /etc/tor/torrc <<EOF
ORPort 9001
# Nickname mynick
RelayBandwidthRate 1000 KB  # Throttle traffic to 1000KB/s (800Kbps)
RelayBandwidthBurst 2000 KB # But allow bursts up to 2000KB/s (1600Kbps)

AccountingMax 1000 GB
AccountingStart month 1 01:00

# ContactInfo Super Foo <superfoo@mydomainname.random>
## You might also include your PGP or GPG fingerprint if you have one:
#ContactInfo 0xFFFFFFFF Random Person <nobody AT example dot com>

# Doesn't work when AccountingMax is enabled
# DirPort 9030 # what port to advertise for directory connections

# Get fingerprint from /var/lib/tor/fingerprint
#MyFamily keyid,keyid,...

ExitPolicy reject *:* # no exits allowed
EOF

service tor start

# Use this for https://weather.torproject.org/subscribe/
sleep 5
echo "Node fingerprint: $(cat /var/lib/tor/fingerprint)"
