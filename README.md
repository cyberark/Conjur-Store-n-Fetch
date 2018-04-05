# Conjur Store'n'Fetch

A walkthrough of [Conjur.org](https://www.conjur.org) installation and core
secrets workflows.

## Overview

Conjur is a production-ready solution for DevOps security. Follow this
walkthrough to get set up with Conjur software and tour some core workflows:

* Create and use a machine identity
* Apply a security policy and verify that it is enforced
* Securely vault and retrieve secrets

This tutorial uses the Conjur command-line interface, but you don't need to be
an expert. All the commands you need to run, and files you need to create, are
spelled out in explicit detail.

## Preparation

This tutorial has a few prerequisites. They are:

1. A terminal application. [Hyper](https://hyper.is/) is a nice one.
2. The Docker CE package. Visit the [Docker website][docker-ce] and scroll down
   to find the download for your operating system.
3. An account on the CyberArk Conjur Evaluation service.

Sign up here: (PLACEHOLDER: embed widget for creating an account)

[docker-ce]: https://www.docker.com/community-edition
[jq]: https://stedolan.github.io/jq/download/

## Getting Started

Create a project folder and set it as your terminal's current directory:

```
mkdir conjur-eval
cd conjur-eval
```

Then [download `docker-compose.yml`][docker-compose.yml] and put it in the
folder.

###### file:docker-compose.yml
```yaml
version: '2'
services:
  conjur:
    image: cyberark/conjur-cli:5
    working_dir: /root
    volumes:
      - ./:/root
```

[docker-compose.yml]: https://github.com/ryanprior/Conjur-Store-n-Fetch/releases/download/v1-pre/docker-compose.yml

To connect to your account, use the email you provided and the API key you
created:

First, enter your account:
```bash
account="your.email@yourcompany.com"
```

###### Initialize the client
```
docker-compose run conjur init -u https://eval.conjur.org -a ${account}
docker-compose run conjur authn login -u admin
```

When prompted, type (or paste) your API key.

*Tip: save yourself typing with an alias. (optional)*
```sh-session
$ alias conjur="docker-compose run conjur"
```


## Admin & vaulting a secret

When a Conjur account is created, it's a blank slate: all secrets, users,
machines, and other objects in Conjur are part of a security policy. Let's load
a policy containing a variable container in the vault, then store a secret in
there.

### Loading a policy

This policy creates a single varible called `eval/secret`. Download
[one-variable.yml][one-variable.yml] and put it in your folder.

###### file:one-variable.yml
```yaml
- !policy
  id: eval
  body:
    - !variable secret

```

According to this policy, only the Conjur admin should be able to update the
value of our secret.

Here's how to load it into Conjur:

###### Load a policy
```bash
docker-compose run conjur policy load root one-variable.yml
```

The subcommand `policy load root` means that we're loading this policy at the
root level of the account, [like the root of a tree][policy-as-tree]. For more
complicated workloads, you can create nested policies, but we won't use that
feature yet.

_For more about Conjur's policy format and the philosophy beind it, visit
[Reference - Policies][conjur-policy]._

[policy-as-tree]: https://www.conjur.org/blog/2018/03/21/conjur-policy-trees.html
[conjur-policy]: https://www.conjur.org/reference/policy.html

### Vault a secret

Now let's vault a secret into the variable. Vaulted secrets are automatically
secured by encrypting them at rest and in transit. See also: [Reference -
Cryptography][conjur-crypto].

[conjur-crypto]: https://www.conjur.org/reference/cryptography.html

Usually your secret will be something like an API key. Let's create our own fake
faux-API key: the command `openssl rand` creates a random string like.

###### Add a value to a secret
```bash
secret=$(docker-compose run --entrypoint openssl conjur rand -hex 12)
docker-compose run conjur variable values add eval/secret ${secret}
```

### Fetch the secret again (as admin)

Having vaulted our secret, let's fetch it back out again:

###### Fetch a secret
```
docker-compose run conjur variable value eval/secret
```

## Creating & using a machine identity

You should never let your production machines log in as admin. It's too much
responsibility, and there's no need. With Conjur you can easily create a machine
identity to represent your code and let it authenticate to fetch secrets.

### Create a machine identity

Like before, we need a policy that defines a role for our machine. Unlike
before, we're going to define a relationship between a role (the machine) and a
resource (the variable):

###### file:variable-and-host.yml
```yaml
- !policy
  id: eval
  body:
    # The objects:
    - !variable secret
    - !host machine

    # The relationship between the objects:
    - !permit
      role: !host machine
      privileges: [read, execute]
      resource: !variable secret

```

Download [variable-and-host.yml][variable-and-host.yml] and put it in your
folder. Then let's load it:

###### Load variable+host policy
```bash
docker-compose run conjur policy load root variable-and-host.yml | tee host.json
```

### Authenticate using a machine identity (instead of admin)

When you loaded that policy, you got a response with an ID and API key. This is
the data a machine needs to prove its identity. It's now saved as `host.json`.

###### Retrieve the host's API key
```bash
api_key=$(jq -r .api_key host.json | tr -d '\r\n')
```

*Or you can just type `api_key=` and copy-paste the "api-key" data from the
response. But smooth `bash` one-liners make you a code witch. You know.*

###### Login as host
```bash
conjur authn login -u host/eval/machine -p ${api_key}
```

Now you're acting as the host.

### Retrieve a secret using a machine identity

The policy gives this host permission to "read and execute" the variable. In
Conjur permission terms, "read" lets you see the variable and its metadata,
while "execute" lets you actually fetch the value.

###### Fetch a secret just like before
```bash
docker-compose run conjur variable value eval/secret
```

So far so good; and when we try to change the secret's value, we get an error
response because the machine is not authorized by the policy to do so:

###### Attempt to modify the secret
```bash
secret=$(docker-compose run --entrypoint openssl conjur rand -hex 12)
conjur variable values add store-n-fetch/secret ${secret}
```

---

## Addendum: files and scripts

Using `dev.sh` you can generate all the files and scripts as described in this
guide. It uses the Markdown source of this README and pieces it together to
create the files. That makes this a _literate guide_ in the sense of literate
programming.

###### file:bin/start
```bash
#!/usr/bin/env bash
set -eux

echo 'Enter your account:'
read account

<<Initialize the client>>
```

###### file:bin/load-one-variable-policy
```bash
#!/usr/bin/env bash
set -eux

<<Load a policy>>

```

###### file:bin/load-variable-plus-host-policy


###### file:bin/store-secret
```bash
#!/usr/bin/env bash
set -eux

<<Add a value to a secret>>

```

###### file:bin/fetch-secret
```bash
#!/usr/bin/env bash
set -eux

<<Fetch a secret>>

```

###### file:bin/login-as-machine
```bash
#!/usr/bin/env bash
set -eux

<<Retrieve the host's API key>>
<<Login as host>>

```
