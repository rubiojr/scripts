#!/bin/bash
docker create \
       --name influxdb \
       --volume=/var/influxdb/config:/config \
       --volume=/var/influxdb/data:/data \
       -p 8083:8083 \
       -e INFLUXDB_INIT_PWD='secret' \
       -e ADMIN_USER="admin" \
       -e PRE_CREATE_DB="db1" \
       -p 8086:8086 \
       tutum/influxdb
