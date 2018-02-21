#!/usr/bin/env bash -e

docker run --interactive --tty --rm --volume $(pwd):/workdir mqsoh/knot README.md
chmod +x *.sh
cp docker-compose.yml store-n-fetch.yml dist/
