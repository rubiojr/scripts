#!/bin/bash
set -e

SECRET="secret"
SERVERS="server1.com server2.com"
RETRY=

for server in $SERVERS; do
  RETRY+="-retry-join $server "
done

docker run -d --net=host -e 'CONSUL_LOCAL_CONFIG={"leave_on_terminate": true, "disable_remote_exec": true}' consul agent -bind=127.0.0.1 -retry-join=$RETRY
