#!/bin/bash
set -e

if [ `whoami` != 'root' ]; then
  echo "This script requires root."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt-get install -y openssh-server vim tinc \
                   openvpn ntp unattended-upgrades \
                   ntpdate wicd-curses curl avahi-daemon \
                   ufw tcpdump nmap stress

apt-get remove -y --purge libgtk*
apt-get autoremove -y --purge
apt-get clean

mkdir -p /home/pi/.ssh
curl https://github.com/rubiojr.keys > /home/pi/.ssh/authorized_keys
chmod 0700 /home/pi/.ssh
chown -R pi:pi /home/pi/.ssh

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

ufw allow 22/tcp
ufw enable

cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

cat > /boot/config.txt <<EOF
#uncomment to overclock the arm. 700 MHz is the default.
arm_freq=900
# NOOBS Auto-generated Settings:
hdmi_force_hotplug=1
config_hdmi_boost=4
overscan_left=24
overscan_right=24
overscan_top=16
overscan_bottom=16
disable_overscan=0
core_freq=250
sdram_freq=450
over_voltage=2
gpu_mem=16
EOF

cat > /etc/modprobe.d/8192cu.conf <<EOF
# Disable power saving
options 8192cu rtw_power_mgnt=0 rtw_enusbss=1 rtw_ips_mode=1
EOF

service rsyslog stop
find /var/log -type f -exec truncate -s 0 {} \;
update-rc.d rsyslog disable

echo "Done."
echo
echo "TODO:"
echo "* Change the pi user password"
echo "* Fix the hostname"
echo "* Tinc setup"
echo "* Wifi config?"
echo "* Reboot"
