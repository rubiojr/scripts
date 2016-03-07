#!/bin/bash
set -e

if [ `whoami` != "root" ]; then
  echo 'Run as root.'
  exit 1
fi

if [ -t 2 ]; then
  exec 2> >(while read line; do echo -e "\e[01;31m$line\e[0m" >&2; done)
fi

VERSION=0.6.3
ARCH=amd64
CONSUL_URL="https://releases.hashicorp.com/consul/$VERSION/consul_${VERSION}_linux_$ARCH.zip"

bootstrap(){
  apt-get update -qq
  apt-get install -qq -y wget unzip
  wget --quiet $CONSUL_URL -O /tmp/consul.zip
  cd /usr/local/bin
  unzip -o /tmp/consul.zip > /dev/null
  adduser --quiet --system --home /var/lib/consul consul
  touch /var/log/consul.log
  mkdir -p /var/lib/consul
  mkdir -p /etc/consul.d
  chown consul /var/log/consul.log
  chown -R consul /var/lib/consul
}

upstart_service(){
  cat > /etc/init/consul.conf <<EOF
description "Consul agent"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

setuid consul
setgid nogroup

script
  if [ -f "/etc/default/consul" ]; then
    . /etc/default/consul
  fi

  # Make sure to use all our CPUs, because Consul can block a scheduler thread
  export GOMAXPROCS=`nproc`

  # Get the public IP
  DEFAULT_IFACE=$(route | grep default | awk '{print $8}')
  IFACE=\${CONSUL_NETIF:-\$DEFAULT_IFACE}
  BIND=\`ifconfig \$IFACE | grep "inet addr" | awk '{ print substr(\$2,6) }'\`

  exec /usr/local/bin/consul agent \
    -config-dir="/etc/consul.d" \
    -bind=\$BIND \
    -data-dir=/var/lib/consul \
    \${CONSUL_FLAGS} \
    >>/var/log/consul.log 2>&1
end script
EOF
}

start_service(){
  status consul | grep stop
  if [ $? == 0 ]; then
    start consul
  else
    restart consul
  fi
}

case "$1" in
  agent)
    bootstrap
    ;;
  server)
    bootstrap
    echo "CONSUL_FLAGS=-server" >> /etc/default/consul
    echo "#CONSUL_NETIF=eth0" >> /etc/default/consul
    ;;
  *)
    echo "Usage: $0 <role>"
    echo "Role is either agent or server"
    exit 1
    ;;
esac

upstart_service
start_service
