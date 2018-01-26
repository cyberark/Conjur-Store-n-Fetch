#!/usr/bin/env bash -ex

docker-compose exec client bash -c \
               "curl -vsSL -H \"\$(conjur authn authenticate -H)\" \
               --data \"$(uuidgen)\" \
               http://conjur/secrets/test/variable/demo/secret"
