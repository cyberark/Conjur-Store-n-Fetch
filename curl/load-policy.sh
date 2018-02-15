#!/usr/bin/env bash -ex

docker-compose exec client bash -c \
               "curl -vsSL -H \"\$(conjur authn authenticate -H)\" \
                     -X PUT -d \"$(cat policy/demo.yml)\" \
                     http://conjur/policies/test/policy/root"
