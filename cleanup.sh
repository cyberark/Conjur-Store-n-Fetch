#!/usr/bin/env bash

if [[ -f 'docker-compose.yml' ]]; then
    docker-compose down
fi

rm -f \
   account.out \
   host.json \
   token.json \
   create-host.sh \
   docker-compose.yml \
   fetch-secret.sh \
   load-policy.sh \
   login-as-admin.sh \
   login-as-host.sh \
   start.sh \
   store-n-fetch.yml \
   store-secret.sh
