# Conjur Store'n'Fetch

A walkthrough of Conjur.org installation and core secrets workflows.

## Overview

Conjur is a production-ready solution for DevOps security. The goal of this
walkthrough is to get set up with Conjur software, then tour its primary
workflows:

* create and use a machine identity
* apply a security policy and verify that it is enforced
* securely vault and retrieve secrets

## Installation

This tutorial has a few prerequisites. They are:

1. a terminal application. [Hyper](https://hyper.is/) is a nice one.
2. the Docker CE package. Visit the [Docker website][docker-ce] and scroll down
   to find the download for your operating system.

[docker-ce]: https://www.docker.com/community-edition

## Getting Started

Docker makes it easy to install the Conjur software by using "images," which
offer service-level packages for the components that Conjur needs to run. We've
extended by creating a Docker image for Conjur. All you need to do to download
all the rest of the software necessary for the guide is to run this command:

###### Downloading Conjur using Docker
```bash
# Pull required container images from Docker Hub
docker-compose pull
```

This instructs `docker-compose` to look at the services manifest in the file
`docker-compose.yml` and download the necessary images.

### Services

Conjur requires a minimum of two services to run, and we'll include a third
service to act like a client machine that's using and administrating Conjur.

Conjur uses a standard Postgres database. This can be self-hosted or managed by
a cloud provider like Amazon RDS. Here's the configuration for a Docker
container that can serve as our Postgres database:

###### Database Service
```yaml
database:
  image: postgres:9.3
```

The Conjur service uses an image automatically published by CyberArk from the
latest builds of our open source project. It depends on the database service for
storage, and it needs a data key from the enviornment which it will use to
encrypt secrets at rest.

###### Conjur Service
```yaml
conjur:
  image: cyberark/conjur
  command: server
  environment:
    DATABASE_URL: postgres://postgres@database/postgres
    CONJUR_DATA_KEY:
  depends_on: [ database ]
```

The client service is not necessary to run Conjur, but it's convenient for
learning. It has the Conjur command-line tool pre-installed, plus other useful
utilities. It also provides the `policy` and `json` folders to the service as
"volumes," so that the client can access those files.

###### Client Service
```yaml
client:
  image: conjurinc/cli5
  depends_on: [ conjur ]
  entrypoint: sleep
  command: infinity
  volumes:
    - ./policy:/mnt/policy
    - ./json:/mnt/json
```

The container images used by these three services are `postgres`,
`cyberark/conjur`, and `conjurinc/cli5`. Each image contains all the necessary
components to run its service, and when you run `docker-compose pull` Docker
will download those images automatically.

### Starting the Conjur server and configuring the client

First, if you've run through this guide before, run this command to delete your
data, clean up and give yourself a clean enviornment:

###### Cleanup
```bash
# Remove containers and files created in earlier runs (if any)
docker-compose down
rm -f json/* data_key test.out
```

Next we'll need to generate a master data key to encrypt our secrets at rest:

###### Generate a data key
```bash
# Generate a data key for Conjur encryption of data at rest.
# *** Prevent data loss: ***
# Move this key to a safe place before deploying in production!
docker-compose run --no-deps --rm conjur data-key generate > data_key
export CONJUR_DATA_KEY="$(< data_key)"
```

Now we're ready to start the Conjur server:

###### Start Conjur
```bash
# Start services and wait a little while for them to become responsive
docker-compose up -d
docker-compose exec conjur conjurctl wait
```

Before adding data to Conjur, we'll need to create an organizational account.
You can have as many accounts as you want, but to start we'll just create one
called "test:"

###### Create an organizational account
```bash
# Create a new account in Conjur
docker-compose exec conjur conjurctl account create test | tee test.out
```

Now Conjur is running and we're ready to initialize the client so that it can
connect:

###### Initialize the client
```
# Initialize the Conjur client
docker-compose exec client bash -c "conjur init -u http://conjur -a test"
```

Now that we've finished those steps, let's review progress. We have:

* downloaded all the necessary software to run a Postgres database, Conjur
  server, and Conjur client
* configured those services to run in a set of Docker containers
* generated a data key for Conjur to encrypt secrets at rest
* initialized a Conjur server and Conjur account

## Logging in as Admin & vaulting a secret

###### Retrieve the admin API key
```bash
api_key="$(grep API test.out | cut -d: -f2 | tr -d ' \r\n')"
```

###### Login as admin
```bash
docker-compose exec client conjur authn login -u admin -p $api_key
```

###### whoami
```bash
docker-compose exec client conjur authn whoami
```

### Loading a policy

###### file:policy/demo.yml
```yaml
- !policy
  id: demo
  annotations:
    description: policy for demo of storing & fetching secrets using Conjur
  body:
    - !layer
    - !host_factory
      layers: [ !layer ]
    - !variable secret
    - !permit
      resource: !variable secret
      privilege: [ read, execute ]
      role: !layer

```

###### Load a policy
```bash
docker-compose exec client conjur policy load root /mnt/policy/demo.yml
```

### Vault a secret

###### Add a value to a secret
```bash
docker-compose exec client conjur variable values add demo/secret $(uuidgen)
```

### Fetch the secret again (as admin)

###### Fetch a secret
```
docker-compose exec client conjur variable value demo/secret
```

## Creating & using a machine identity

### Create a machine identity
###### Create a hostfactory token
```bash
docker-compose exec client conjur hostfactory tokens create demo >json/token
token=$(jq -r .[].token json/token | tr -d '\n\r')
echo "created a host factory token: $token"
```

###### Use hostfactory token to create a host
```bash
docker-compose exec client conjur hostfactory hosts create $token demo-host >json/host
```

###### Revoke a hostfactory token
```bash
docker-compose exec client conjur hostfactory tokens revoke $token
```

### Authenticate using a machine identity (instead of admin)

###### Retrieve the host's API key
```bash
api_key=$(jq -r .api_key json/host | tr -d '\r\n')
```

###### Login as host
```bash
docker-compose exec client conjur authn login -u host/demo-host -p $api_key
```

### Retrieve a secret using a machine identity

###### Fetch a secret just like before
```bash
docker-compose exec client conjur variable value demo/secret
```

When we try to change the secret's value, we get an error response because the
machine identity is not authorized by the policy to do so.

###### Attempt to modify the secret
```bash
docker-compose exec client conjur variable values add demo/secret $(uuidgen)
```


## Addendum: files and scripts

You can generate all the files and scripts used in this guide from this
documentation.

###### file:start.sh
```bash
#!/usr/bin/env bash -e

<<Downloading Conjur using Docker>>

<<Cleanup>>

<<Generate a data key>>

<<Start Conjur>>

<<Create an organizational account>>

<<Initialize the client>>

```

###### file:docker-compose.yml
```yaml
version: '2'
services:
  <<Database Service>>

  <<Conjur Service>>

  <<Client Service>>

```

###### file:login-as-admin.sh
```bash
#!/usr/bin/env bash -ex

# *** Protect your secrets: ***
# Rotate the admin's API key regularly!
<<Retrieve the admin API key>>
<<Login as admin>>
<<whoami>>

```

###### file:load-policy.sh
```bash
#!/usr/bin/env bash -ex

<<Load a policy>>

```

###### file:store-secret.sh
```bash
#!/usr/bin/env bash -ex

<<Add a value to a secret>>

```

###### file:fetch-secret.sh
```bash
#!/usr/bin/env bash -ex

<<Fetch a secret>>

```

###### file:create-host.sh
```bash
#!/usr/bin/env bash -e

<<Create a hostfactory token>>

<<Use hostfactory token to create a host>>

<<Revoke a hostfactory token>>

```
###### file:login-as-host.sh
```bash
#!/usr/bin/env bash -ex

<<Retrieve the host's API key>>
<<Login as host>>
<<whoami>>

```
