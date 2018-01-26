#!/usr/bin/env bash -e

source util.sh

conjur hostfactory tokens create demo >json/token
token=$(jq -r .[].token /mnt/json/token | tr -d '\n\r')
echo "created a host factory token: $token"

conjur hostfactory hosts create $token demo-host >json/host
echo "created a new host using the token"

conjur hostfactory tokens revoke $token
echo "destroyed the token"
