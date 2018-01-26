#!/usr/bin/env bash -ex

source util.sh

# *** Protect your secrets: ***
# Rotate the admin's API key regularly!
api_key="$(grep API test.out | cut -d: -f2 | tr -d ' \r\n')"
conjur authn login -u admin -p $api_key
conjur authn whoami
