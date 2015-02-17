#!/bin/bash
# Test with mosquitto_sub --insecure  --cafile /etc/mosquitto/certs/ca.crt -h mqtt2.rbel.co -t '#'
set -e

if [ `whoami` != 'root' ]; then
  exec sudo $0 $@
fi

BASE_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ ! -f /etc/apt/sources.list.d/mosquitto-dev-mosquitto-ppa-trusty.list ]; then
  apt-get install -y software-properties-common || \
    apt-get install -y python-software-properties
  add-apt-repository ppa:mosquitto-dev/mosquitto-ppa
fi

dpkg -s mosquitto | grep -q 'Version: 1' || {
  apt-get update && apt-get install -y mosquitto mosquitto-clients
}

MOSQUITTOUSER=mosquitto TARGET=/etc/mosquitto/certs $BASE_PATH/generate-CA.sh octox

cat > /etc/mosquitto/conf.d/ssl.conf <<EOF
cafile /etc/mosquitto/certs/ca.crt
keyfile /etc/mosquitto/certs/octox.key
certfile /etc/mosquitto/certs/octox.crt
use_identity_as_username false
password_file /etc/mosquitto/passwd
require_certificate false
EOF

cat > /etc/mosquitto/passwd <<"EOF"
test:$6$R/ChjN7F+bvMIpDG$2PWXkgskuy3WM2fnayHFNwptnxYMnabGHalR0n+3IIcGUKR0UNoAOVXaq+6fLhBXmRvtK/JWJZ1Bf2+K8VBFMA==
EOF

if service mosquitto status | grep stop; then
  service mosquitto start
else
  service mosquitto restart
fi
