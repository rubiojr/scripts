#!/bin/bash
set -e
LUSER=$1
IP=$2
ROOTFS="/var/lib/lxc/user-$LUSER/rootfs"
SSHKEY=$3

usage() {
  echo "Usage: $0 <username> <IP> [ssh_key]"
}

prepare_key() {
  ip=$1
  tmp_ssh_key=`mktemp`
  if [[ $SSHKEY =~ ^http ]]; then
    curl --silent $SSHKEY > $tmp_ssh_key
  else
    if [ -f "$SSHKEY" ]; then
      cp $SSHKEY $tmp_ssh_key
    else
      echo Invalid SSH key file
    fi
  fi
}

[ -z "$LUSER" ] && {
  usage
  exit 1
}

[ -z "$IP" ] && {
  usage
  exit 1
}

[ -d $ROOTFS ] && {
  echo User container for $LUSER already exists.
  exit 1
}

lxc-create -n user-$LUSER -t ubuntu
sed -i "s/^#PasswordAuthentication yes/PasswordAuthentication no/" $ROOTFS/etc/ssh/sshd_config

cat > $ROOTFS/etc/profile.d/history.sh << EOF
#!/bin/bash
export HISTFILE=/dev/null
EOF

chroot $ROOTFS useradd --shell /bin/bash $LUSER
chroot $ROOTFS userdel -f ubuntu

[ -z "$SSHKEY" ] || {
  mkdir -p $ROOTFS/home/$LUSER/.ssh

  prepare_key $IP

  cp $tmp_ssh_key $ROOTFS/home/$LUSER/.ssh/authorized_keys
  echo -n "command="/usr/local/bin/sshproxy $IP 22",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty " >> /home/sshproxy/.ssh/authorized_keys
  cat $tmp_ssh_key >> /home/sshproxy/.ssh/authorized_keys

  chroot $ROOTFS chown $LUSER:$LUSER /home/$LUSER -R
  chmod 700 $ROOTFS/home/$LUSER/.ssh
}

echo "lxc.network.ipv4 = $IP/24" >> $ROOTFS/../config
