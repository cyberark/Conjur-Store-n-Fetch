#!/usr/bin/env bash -ex

source util.sh

conjur variable values add demo/secret $(uuidgen)
