# Conjur Store'n'Fetch

A walkthrough of [Conjur.org](https://www.conjur.org) installation and core
secrets workflows.

## Overview

Conjur is a production-ready solution for DevOps security. The goal of this
walkthrough is to get set up with Conjur software, then tour some core
workflows:

* create and use a machine identity
* apply a security policy and verify that it is enforced
* securely vault and retrieve secrets

## Installation

This tutorial has a few prerequisites. They are:

1. A terminal application. [Hyper](https://hyper.is/) is a nice one.
2. The Docker CE package. Visit the [Docker website][docker-ce] and scroll down
   to find the download for your operating system.

[docker-ce]: https://www.docker.com/community-edition
[jq]: https://stedolan.github.io/jq/download/

## Getting Started

Docker makes it easy to install the Conjur software. You tell it what services
you want, and it pretty much handles the rest.

The first thing you'll want to do is create a folder, then save the following
inside it as `docker-compose.yml`

###### file:docker-compose.yml
```yaml
version: '2'
services:
  database:
    image: postgres:9.3

  conjur:
    image: cyberark/conjur
    command: server
    environment:
      DATABASE_URL: postgres://postgres@database/postgres
      CONJUR_DATA_KEY:
    depends_on: [ database ]

  client:
    image: conjurinc/cli5
    depends_on: [ conjur ]
    entrypoint: sleep
    command: infinity
    working_dir: /mnt
    volumes:
      - ./:/mnt

```

### Overview of the services

Conjur uses a standard Postgres database. This can be self-hosted or managed by
a cloud provider like Amazon RDS. For now we'll host locally using Docker.

The Conjur service itself uses an image automatically published by CyberArk from
the latest builds of our open source project. It depends on the database service
for storage, and it needs a data key from the environment which it will use to
[encrypt secrets at rest][conjur-encryption].

[conjur-encryption]: https://www.conjur.org/reference/cryptography.html

The client service is not necessary to run Conjur, but it's convenient for
learning. It has the Conjur command-line tool pre-installed, plus other useful
utilities.

### Downloading the software

The container images used by these three services are `postgres`,
`cyberark/conjur`, and `conjurinc/cli5`. Each image contains all the necessary
components to run its service, and Docker handles downloading and updating
images for you.

To download all the software necessary, run this command in the folder
containing `docker-compose.yml`:

###### Downloading Conjur using Docker
```bash
docker-compose pull
```

---

### Starting the Conjur server and configuring the client

First, if you've run through this guide before, run these commands to delete
your data, clean up and give yourself a fresh enviornment:

###### Cleanup
```bash
docker-compose down
rm -f token.json host.json data_key account.out
```

Next we'll need to generate a master data key to [encrypt our secrets at
rest][conjur-encryption]:

*Prevent data loss:* move this key to a safe place before deploying in
production!

###### Generate a data key
```bash
docker-compose run --no-deps --rm conjur data-key generate > data_key
export CONJUR_DATA_KEY="$(cat data_key)"
```

Now we're ready to start the Conjur server:

###### Start Conjur
```bash
docker-compose up -d
docker-compose exec conjur conjurctl wait
```

Before adding data to Conjur, we'll need to create an organizational account.
You can have as many accounts as you want, but to start we'll just create one
called "test:"

###### Create an organizational account
```bash
docker-compose exec conjur conjurctl account create store-n-fetch | tee account.out
```

Now Conjur is running and we're ready to initialize the client so that it can
connect:

###### Initialize the client
```
# Initialize the Conjur client
docker-compose exec client bash -c "conjur init -u http://conjur -a store-n-fetch"
```

Now that we've finished those steps, let's review progress. We have:

* downloaded all the necessary software to run a Postgres database, Conjur
  server, and Conjur client
* configured those services to run in a set of Docker containers
* generated a data key for Conjur to [encrypt secrets at
  rest][conjur-encryption]
* initialized a Conjur server and Conjur account

## Logging in as Admin & vaulting a secret

Up to this point, we have been running our commands in the normal context of
your operating system, which is to say, on the "host computer." But from here on
out, we will be running commands inside the context of the "client" container.
That way, we have access to all the software that's installed as part of the
standard Conjur client.

To start a terminal session inside the container, run:

```bash
docker-compose exec client bash
```

Now your terminal prompt will change to something like:

```sh-session
root@c0ef742d884b:/mnt#
```

That means you're inside the client container and ready to use the Conjur CLI.
The first thing we'll do is to log in and load a policy.

###### Retrieve the admin API key from the new account we created
```bash
api_key="$(grep API account.out | cut -d: -f2 | tr -d ' \r\n')"
```

###### Login as admin
```bash
conjur authn login -u admin -p $api_key
```

###### whoami
```bash
conjur authn whoami
```

### Loading a policy

Right now our Conjur database is empty: apart from the "admin" user and a few
other objects that were automatically created for you, we're at a blank slate.

The next thing to do is to load a security policy, which will create some
objects we can use. The purpose of a policy is to model the parts of your
applicaitons that have secrets, and the people and machines that need access to
those secrets, so that all access can be automatically authorized.

This policy creates a single varible called `store-n-fetch/secret` and a layer
called `store-n-fetch`. It permits hosts that are members of that layer to
fetch, but not update, the secret. In addition, it creates a "host factory"
service that allows you to bootstrap machine identity on hosts, automatically
adding them into our "store-n-fetch" layer.

According to this policy, only the Conjur admin should be able to update the
value of our secret, but all the hosts in our layer should be able to read it.
As we go, we'll test to make sure this is true.

Here's the policy file we'll load:

###### file:store-n-fetch.yml
```yaml
- !policy
  id: store-n-fetch
  annotations:
    purpose: demonstrate storing & fetching secrets using Conjur
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

Here's how to load it into Conjur:

###### Load a policy
```bash
conjur policy load root store-n-fetch.yml
```

The subcommand `policy load root` means that we're loading this policy at the
root level (top-most part of the hierarchy) of Conjur. For more complicated
workloads, you can create nested policies, but we won't use that feature yet.

_For more about Conjur's policy format and the philosophy beind it, visit
[Reference - Policies][conjur-policy]._

[conjur-policy]: https://www.conjur.org/reference/policy.html

### Vault a secret

Now, seeing as we're logged in as admin, let's "vault" a secret by storing it in
a Conjur variable. Vaulted secrets are automatically secured by [encrypting them
with the data key][conjur-encryption].

The command `openssl rand` creates a random string, which is a good option for a
secret to be used by machines.

###### Add a value to a secret
```bash
conjur variable values add store-n-fetch/secret $(openssl rand -hex 16)
```

### Fetch the secret again (as admin)

Having vaulted our secret, let's fetch it back out again:

###### Fetch a secret
```
conjur variable value store-n-fetch/secret
```

## Creating & using a machine identity

You should never let your production machines log in as admin. It's too much
responsibility, and there's no need! With Conjur you can easily create a machine
identity to represent your code and let it authenticate to fetch secrets.

### Create a machine identity
###### Create a hostfactory token
```bash
conjur hostfactory tokens create --duration-minutes=5 store-n-fetch | tee token.json
token=$(jq -r .[].token token.json | tr -d '\n\r')
echo "created a host factory token: $token"
```

We've created a time-limited unforgeable token, a pseudo-secret that will allow
us to bootstrap new machine identities on our hosts for the next five minutes.

Let's create a new host and save its data to `host.json`:

###### Use hostfactory token to create a host
```bash
conjur hostfactory hosts create $token my-host | tee host.json
```

Now that we've created a new host, let's clean up by revoking our token. (If we
didn't, it would automatically expire after the five minute duration that we set
when we created it. But it never hurts to be extra careful.)

###### Revoke a hostfactory token
```bash
conjur hostfactory tokens revoke $token
```

### Authenticate using a machine identity (instead of admin)

Take a look at the data we saved for our new host. It has an ID and an API key,
which is all we need to authenticate using the host's machine identity:

###### Retrieve the host's API key
```bash
api_key=$(jq -r .api_key host.json | tr -d '\r\n')
```

###### Login as host
```bash
conjur authn login -u host/my-host -p $api_key
```

### Retrieve a secret using a machine identity

Recall that we permitted the `store-n-fetch` layer, of which our host is a
member, to fetch but not change the value of our secret. Let's verify that this
works as intended:

###### Fetch a secret just like before
```bash
conjur variable value store-n-fetch/secret
```

So far so good; and when we try to change the secret's value, we get an error
response because the machine identity is not authorized by the policy to do so:

###### Attempt to modify the secret
```bash
conjur variable values add store-n-fetch/secret $(openssl rand -hex 16)
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
Knot writing file: ./store-n-fetch.yml
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
#!/usr/bin/env bash
set -e

# Pull required container images from Docker Hub
<<Downloading Conjur using Docker>>

# Remove containers and files created in earlier runs (if any)
<<Cleanup>>

# Generate a data key for Conjur encryption of data at rest.
<<Generate a data key>>

# Start services and wait a little while for them to become responsive
<<Start Conjur>>

# Create a new account in Conjur
<<Create an organizational account>>

# Prepare the client to connect to the Conjur server
<<Initialize the client>>

```

###### file:login-as-admin.sh
```bash
#!/usr/bin/env bash
set -ex

# *** Protect your secrets: ***
# Rotate the admin's API key regularly!
<<Retrieve the admin API key from the new account we created>>
<<Login as admin>>
<<whoami>>

```

###### file:load-policy.sh
```bash
#!/usr/bin/env bash
set -ex

<<Load a policy>>

```

###### file:store-secret.sh
```bash
#!/usr/bin/env bash
set -ex

<<Add a value to a secret>>

```

###### file:fetch-secret.sh
```bash
#!/usr/bin/env bash
set -ex

<<Fetch a secret>>

```

###### file:create-host.sh
```bash
#!/usr/bin/env bash
set -e

<<Create a hostfactory token>>

<<Use hostfactory token to create a host>>

<<Revoke a hostfactory token>>

```
###### file:login-as-host.sh
```bash
#!/usr/bin/env bash
set -ex

<<Retrieve the host's API key>>
<<Login as host>>
<<whoami>>

```
