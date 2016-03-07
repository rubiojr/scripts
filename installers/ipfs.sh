#!/bin/bash
set -e

if [ `whoami` != "root" ]; then
  echo 'Run as root.'
  exit 1
fi

if [ -t 2 ]; then
  exec 2> >(while read line; do echo -e "\e[01;31m$line\e[0m" >&2; done)
fi

ARCH=amd64
V=0.3.11
URL="https://gobuilder.me/get/github.com/ipfs/go-ipfs/cmd/ipfs/ipfs_v${V}_linux-$ARCH.zip"
TARGET=$(mktemp -u)

bootstrap(){
  echo "Installing IPFS..."
  apt-get update -qq || true
  apt-get install -qq -y wget unzip
  wget --quiet $URL --continue -O $TARGET
  cd /tmp
  rm -rf ipfs
  unzip $TARGET >/dev/null
  mv ipfs/ipfs /usr/local/bin
  rm -rf ipfs
  adduser --quiet --system --shell /bin/bash --home /home/ipfs ipfs
}

upstart_service(){
  echo "Setting up services..."

  cat > /etc/init/ipfs.conf <<EOF
  description "ipfs daemon"

  setuid ipfs
  env HOME=/home/ipfs/

  start on runlevel [2345]
  stop on runlevel [016]
  respawn

  exec /usr/local/bin/ipfs daemon --init
EOF

}

start_service(){
  echo "Starting services..."
  if status ipfs | grep stop; then
    start ipfs 
  fi
}

if [ "$1" = "implode" ]; then
  echo "Removing ipfs from the system..."
  stop ipfs || true
  rm -rf /home/ipfs
  rm -f /usr/local/bin/ipfs
else
  bootstrap
  upstart_service
  start_service
fi
