#!/bin/bash
set -e

if [ `whoami` != 'root' ]; then
  echo "This script requires root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get install -y openssh-server vim tinc \
                   openvpn ntp unattended-upgrades \
                   ntpdate
apt-get remove -y --purge libgtk*
apt-get autoremove --purge
apt-get clean

# CHANGEME
echo 'pi:$ecret00' | chpasswd

sed -i "s/.*PasswordAuthentication.*/PasswordAuthentication no/" /etc/ssh/sshd_config
sed -i "s/.*PermitRootLogin.*/PermitRootLogin without-password/" /etc/ssh/sshd_config

service ntp stop

echo "Etc/UTC" > /etc/timezone
dpkg-reconfigure -f noninteractive tzdata
ntpdate pool.ntp.org

service cron restart
service rsyslog restart
service ntp start
service ssh restart

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

echo "Done"
echo "Make sure to change the pi user password"
