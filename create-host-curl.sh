#!/usr/bin/env bash -e

source util.sh

one_hour_in_future="$(date -v +1H -u +"%Y-%m-%dT%H:%M:%SZ")"

docker-compose exec client bash -c \
               "curl -vsSL -H \"\$(conjur authn authenticate -H)\" \
               -X POST \
               --data-urlencode \"host_factory=test:host_factory:demo\" \
               --data-urlencode \"expiration=$one_hour_in_future\" \
               -o /mnt/json/token-curl \
               http://conjur/host_factory_tokens"

token=$(jq -r .[].token /mnt/json/token-curl | tr -d '\r\n')
echo "created a host factory token: $token"

auth_header="Authorization: Token token=\\\"$token\\\""
docker-compose exec client bash -c \
               "curl -vsSL \
               -X POST \
               --data-urlencode id=demo-curl-host \
               --header \"$auth_header\" \
               -o /mnt/json/host-curl \
               http://conjur/host_factories/hosts"
echo "created a new host using the token"

docker-compose exec client bash -c \
               "curl -vsSL -H \"\$(conjur authn authenticate -H)\" \
               -X DELETE \
               http://conjur/host_factory_tokens/$token"
echo "destroyed the token"
