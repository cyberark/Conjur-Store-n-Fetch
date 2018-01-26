function conjur {
    docker-compose exec client conjur $@
}

function jq {
    docker-compose exec client jq $@
}

function curl_conjur {
    docker-compose exec client bash -c "curl -sSl -H \$(conjur authn authenticate -H) \"$@\""
}
