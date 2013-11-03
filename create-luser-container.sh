#!/bin/bash
set -e
LUSER=$1
ROOTFS="/var/lib/lxc/user-$LUSER/rootfs"

[ -z "$LUSER" ] && {
  echo "Usage: $0 <username>"
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
