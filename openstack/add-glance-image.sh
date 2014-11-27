#!/bin/bash
# Usage: add-glace-image <image-file>
#
# Adds a RAW image to DreamCompute using curl
#
set -e

# DreamCompute credentials
tenant_name="CHANGE ME"
username="CHANGE ME"
password="CHANGE ME"

json='
{
  "auth":
  {
    "tenantName": "'"$tenant_name"'",
    "passwordCredentials": {
      "username": "'"$username"'", "password": "'"$password"'"
    }
  }
}
'

# Get a scoped token from keystone
token=$(curl -s \
  -H "Content-type: application/json" \
  -d "$json" \
  https://keystone.dream.io/v2.0/tokens | \
  python -c 'import sys, json; print json.load(sys.stdin)["access"]["token"]["id"]'
)

curl -i -k -X POST \
           -H "X-Auth-Token: $token" \
           -H "X-Image-Meta-Name: ghe-$(date +%F-%H:%M:%S)" \
           -H "X-Image-Meta-disk_format: raw" \
           -H "x-image-meta-container_format: bare" \
           -H "Content-Type: application/octet-stream" \
           --data-binary @$1 \
           https://image.dream.io:9292/v1/images