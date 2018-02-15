#!/usr/bin/env bash -ex

source util.sh

api_key=$(jq -r .api_key /mnt/json/host-curl | tr -d '\r\n')
conjur authn login -u host/demo-curl-host -p $api_key
conjur authn whoami
