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

1. A terminal application. [Hyper](https://hyper.is/) is a nice one
2. The Docker CE package. Visit the [Docker website][docker-ce] and scroll down
   to find the download for your operating system
3. The JSON query tool `jq`, [available here][jq]

[docker-ce]: https://www.docker.com/community-edition
[jq]: https://stedolan.github.io/jq/download/

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

---

## Addendum: files and scripts

Using `dev.sh` you can generate all the files and scripts as described in this
guide. It uses the Markdown source of this README and pieces it together to
create the files. That makes this a _literate guide_ in the sense of literate
programming.

Example:

```sh-session
bash-3.2$ git clone git@github.com:ryanprior/Conjur-Store-n-Fetch.git
Cloning into 'Conjur-Store-n-Fetch'...
remote: Counting objects: 31, done.        
remote: Compressing objects: 100% (21/21), done.        
remote: Total 31 (delta 5), reused 31 (delta 5), pack-reused 0        
Receiving objects: 100% (31/31), 7.45 KiB | 149.00 KiB/s, done.
Resolving deltas: 100% (5/5), done.
bash-3.2$ cd Conjur-Store-n-Fetch/
bash-3.2$ ./dev.sh
Knot writing file: ./create-host.sh
Knot writing file: ./docker-compose.yml
Knot writing file: ./fetch-secret.sh
Knot writing file: ./load-policy.sh
Knot writing file: ./login-as-admin.sh
Knot writing file: ./login-as-host.sh
Knot writing file: ./policy/demo.yml
Knot writing file: ./start.sh
Knot writing file: ./store-secret.sh
bash-3.2$ ./start.sh
Pulling database (postgres:9.3)...
9.3: Pulling from library/postgres
Digest: sha256:1ea4216d3f91122a12f4fde5eb4de54865d93f914e843dc0f99597ca8b9b47da
Status: Image is up to date for postgres:9.3
Pulling conjur (cyberark/conjur:latest)...
latest: Pulling from cyberark/conjur
Digest: sha256:80a59c143422474ebefa276e89ac12933c84519a0f3d4c283bd596e0dd3d42c6
Status: Image is up to date for cyberark/conjur:latest
Pulling client (conjurinc/cli5:latest)...
latest: Pulling from conjurinc/cli5
Digest: sha256:d7e2cefd664a847f4a2d28eb843b9630ca633727b6de0f0cc3d71fa0f6d74b76
Status: Image is up to date for conjurinc/cli5:latest
Stopping conjurstorenfetch_client_1   ... 
Stopping conjurstorenfetch_conjur_1   ... 
Stopping conjurstorenfetch_database_1 ... 
Removing conjurstorenfetch_client_1   ... 
Removing conjurstorenfetch_conjur_1   ... 
Removing conjurstorenfetch_database_1 ... 
Removing network conjurstorenfetch_default
Creating network "conjurstorenfetch_default" with the default driver
Creating conjurstorenfetch_database_1 ... 
Creating conjurstorenfetch_conjur_1   ... 
Creating conjurstorenfetch_client_1   ... 
Waiting for Conjur to be ready...
.... Conjur is ready!
Created new account account 'test'
Token-Signing Public Key: -----BEGIN PUBLIC KEY-----
[[ a public key was here ]]
-----END PUBLIC KEY-----
API key for admin: [[ an api key was here ]]
Wrote configuration to /root/.conjurrc
bash-3.2$
```

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
