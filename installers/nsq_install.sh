#!/bin/bash
set -e

if [ `whoami` != "root" ]; then
  echo 'Run as root.'
  exit 1
fi

if [ -t 2 ]; then
  exec 2> >(while read line; do echo -e "\e[01;31m$line\e[0m" >&2; done)
fi

URL="https://s3.amazonaws.com/bitly-downloads/nsq/nsq-0.3.1.linux-amd64.go1.4.1.tar.gz"
TARGET=$(mktemp -u)

bootstrap(){
  echo "Installing NSQ..."
  apt-get update -qq
  apt-get install -qq -y wget unzip
  wget --quiet $URL --continue -O $TARGET
  cd /tmp
  tar xzf $TARGET
  mv nsq-*/bin/* /usr/local/bin/
  rm -rf nsq* $TARGET
  mkdir -p /srv/nsq
  adduser --quiet --system --home /srv/nsq nsq 
  chown -R nsq /srv/nsq
}

upstart_service(){
  echo "Setting up services..."

  if [ ! -f /etc/default/nsqd ]; then
    echo "#NSQ_LOOKUPD_ADDRESS=127.0.0.1:4160" > /etc/default/nsqd
    echo "#NSQD_HTTP_ADDRESS=127.0.0.1:4151"   >> /etc/default/nsqd
    echo "#NSQD_TCP_ADDRESS=127.0.0.1:4150"   >> /etc/default/nsqd
  fi

  if [ ! -f /etc/default/nsqlookupd ]; then
    echo "#NSQ_LOOKUPD_TCP_ADDRESS=127.0.0.1:4160" > /etc/default/nsqlookupd
    echo "#NSQ_LOOKUPD_HTTP_ADDRESS=127.0.0.1:4161" >> /etc/default/nsqlookupd
  fi

  cat > /etc/init/nsqd.conf <<EOF
description "NSQ daemon"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

setuid nsq 
setgid nogroup

script
  if [ -f "/etc/default/nsqd" ]; then
    . /etc/default/nsqd
  fi

  # Make sure to use all our CPUs
  export GOMAXPROCS=`nproc`

  NSQD_TCP_ADDRESS=\${NSQD_TCP_ADDRESS:-127.0.0.1:4150}
  NSQD_HTTP_ADDRESS=\${NSQD_HTTP_ADDRESS:-127.0.0.1:4151}
  NSQ_LOOKUPD_ADDRESS=\${NSQ_LOOKUPD_ADDRESS:-127.0.0.1:4160}

  LHOSTS=''
  for addr in \$(echo \$NSQ_LOOKUPD_ADDRESS | sed -n 1'p' | tr ',' '\n'); do
    LHOSTS="-lookupd-tcp-address=\$addr \$LHOSTS"
  done

  exec /usr/local/bin/nsqd \
    \$LHOSTS \
    -http-address=\$NSQD_HTTP_ADDRESS \
    -tcp-address=\$NSQD_TCP_ADDRESS \
    -data-path=/srv/nsq
end script
EOF

  cat > /etc/init/nsqlookupd.conf<<EOF
description "NSQ lookupd daemon"

start on runlevel [2345]
stop on runlevel [!2345]

respawn

setuid nsq
setgid nogroup

script
  if [ -f "/etc/default/nsqlookupd" ]; then
    . /etc/default/nsqlookupd
  fi

  # Make sure to use all our CPUs
  export GOMAXPROCS=`nproc`

  NSQ_LOOKUPD_TCP_ADDRESS=\${NSQ_LOOKUPD_TCP_ADDRESS:-127.0.0.1:4160}
  NSQ_LOOKUPD_HTTP_ADDRESS=\${NSQ_LOOKUPD_HTTP_ADDRESS:-127.0.0.1:4161}

  exec /usr/local/bin/nsqlookupd -http-address=\$NSQ_LOOKUPD_HTTP_ADDRESS \
                                 -tcp-address=\$NSQ_LOOKUPD_TCP_ADDRESS
end script
EOF
}

start_service(){
  echo "Starting services..."
  status nsqlookupd | grep stop || stop nsqlookupd
  start nsqlookupd

  status nsqd | grep stop || stop nsqd
  start nsqd 
}

if [ "$1" = "implode" ]; then
    echo "Removing NSQ from the system..."
    stop nsqd || true
    stop nsqlookupd || true
    rm -rf /srv/nsq
    rm -f /etc/default/nsqd
    rm -f /etc/default/nsqlookupd
    rm -f /etc/init/{nsqd,nsqlookupd}.conf
    rm -f /usr/local/bin/nsqadmin
    rm -f /usr/local/bin/nsqd
    rm -f /usr/local/bin/nsqlookupd
    rm -f /usr/local/bin/nsq_pubsub
    rm -f /usr/local/bin/nsq_stat
    rm -f /usr/local/bin/nsq_tail
    rm -f /usr/local/bin/nsq_to_file
    rm -f /usr/local/bin/nsq_to_http
    rm -f /usr/local/bin/nsq_to_nsq
else
    bootstrap
    upstart_service
    start_service
fi
