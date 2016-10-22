#!/bin/bash
set -e

IP=$(curl -s https://ipinfo.io/ip)
SECRET="secret"
SERVERS="server1 server2"
RETRY=

for server in $SERVERS; do
  RETRY+="-retry-join $server "
done

docker run -d --name consul \
              --net=host \
              -e 'CONSUL_LOCAL_CONFIG={"skip_leave_on_interrupt": true, "disable_remote_exec": true}' \
              consul agent -server -bind=$IP $RETRY -bootstrap-expect=3 -encrypt="$SECRET"


docker run -d --net=host -e 'CONSUL_LOCAL_CONFIG={"leave_on_terminate": true, "disable_remote_exec": true}' consul agent -bind=$IP -retry-join=$RETRY
