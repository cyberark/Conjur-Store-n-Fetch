#!/usr/bin/env bash -ex

source util.sh

api_key=$(jq -r .api_key /mnt/json/host | tr -d '\r\n')
conjur authn login -u host/demo-host -p $api_key
conjur authn whoami
