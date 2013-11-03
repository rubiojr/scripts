#!/bin/bash
set -e
LUSER=$1
ROOTFS="/var/lib/lxc/user-$LUSER/rootfs"
SSHKEY=$2

[ -z "$LUSER" ] && {
  echo "Usage: $0 <username> [ssh_key]"
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

  if [[ $SSHKEY =~ ^http ]]; then
    curl --silent $SSHKEY > $ROOTFS/home/$LUSER/.ssh/authorized_keys
  else
    if [ -f "$SSHKEY" ]; then
      cat $SSHKEY > $ROOTFS/home/$LUSER/.ssh/authorized_keys
    else
      echo Invalid SSH key file
      exit 1
    fi
  fi
  chroot $ROOTFS chown $LUSER:$LUSER /home/$LUSER -R
  chmod 700 $ROOTFS/home/$LUSER/.ssh
}
