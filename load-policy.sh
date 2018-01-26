#!/usr/bin/env bash -ex

source util.sh

conjur policy load root /mnt/policy/demo.yml
