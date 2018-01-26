#!/usr/bin/env bash

source util.sh

# Pull required container images from Docker Hub
docker-compose pull

# Remove containers and files created in earlier runs (if any)
docker-compose down
rm -f json/* data_key test.out

# Generate a data key for Conjur encryption of data at rest.
# *** Prevent data loss: ***
# Move this key to a safe place before deploying in production!
docker-compose run --no-deps --rm conjur data-key generate > data_key
export CONJUR_DATA_KEY="$(< data_key)"

# Start services and wait a little while for them to become responsive
docker-compose up -d
docker-compose exec conjur conjurctl wait

# Create a new account in Conjur
docker-compose exec conjur conjurctl account create test | tee test.out


# Configure the Conjur client and log in as admin
docker-compose exec client bash -c "echo yes | conjur init -u http://conjur -a test"

