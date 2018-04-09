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
3. The `jq` JSON processor. Download from [its website][jq].
3. An account on the CyberArk Conjur Evaluation service. Sign up here: (PLACEHOLDER: embed widget for creating an account)

[docker-ce]: https://www.docker.com/community-edition
[jq]: https://stedolan.github.io/jq/download/

## Getting Started

Create a project folder and set it as your terminal's current directory:

```
mkdir conjur-eval
cd conjur-eval
```

Then download [`docker-compose.yml`][docker-compose.yml] and put it in the
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

[docker-compose.yml]: https://github.com/ryanprior/Conjur-Store-n-Fetch/releases/download/1.0/docker-compose.yml

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

[one-variable.yml]: https://github.com/ryanprior/Conjur-Store-n-Fetch/releases/download/1.0/one-variable.yml

According to this policy, only the Conjur admin should be able to update the
value of our secret.

Here's how to load it into Conjur:

###### Load a policy
```bash
docker-compose run conjur policy load root one-variable.yml
```

The command `policy load root` means that we're loading this policy at the root
level of the account, [like the root of a tree][policy-as-tree]. For more
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
secret=$(docker-compose run --entrypoint openssl conjur rand -hex 12 | tr -d '\r\n')
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
resource (the variable). Download [variable-and-host.yml][variable-and-host.yml]
and put it in your folder.

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

[variable-and-host.yml]: https://github.com/ryanprior/Conjur-Store-n-Fetch/releases/download/1.0/variable-and-host.yml

Now let's load it:

###### Load variable+host policy
```bash
docker-compose run -T conjur policy load root variable-and-host.yml | tee roles.json
```

*Note: the `-T` argument is needed to prevent the "Loaded policy" message from
getting folded into our JSON output.*

### Authenticate using a machine identity (instead of admin)

When you loaded that policy, you got a response with an ID and API key. This is
the data a machine needs to prove its identity. It's now saved as `roles.json`.

###### Retrieve the host's API key
```bash
api_key=$(jq -r '.created_roles | .[].api_key' roles.json | tr -d '\r\n')
```

*Or you can just type `api_key=` and copy-paste the "api-key" data from the
response. But smooth `bash` one-liners make you a code witch. You know.*

**What if I don't get any `created_roles`?**

If you load the `variable-and-host.yml` policy a second time, you'll get a
response like this:

```json
{
  "created_roles": {},
  "version": 2
}
```

This is because policy loads are idempotent in Conjur. You can load the same
policy multiple times and it won't change the state of the system.

If you're going through this flow a second time and want to get the host's API
key, you can rotate it like so:

```
api_key=$(docker-compose run conjur host rotate_api_key -h eval/machine | tr -d '\r\n')
```

Now that you have the host's API key, you can assume its identity:

###### Login as host
```bash
docker-compose run conjur authn login -u host/eval/machine -p ${api_key}
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
secret=$(docker-compose run --entrypoint openssl conjur rand -hex 12 | tr -d '\r\n')
conjur variable values add eval/secret ${secret}
```

Instead of a "Value added" message, you'll get `error: 403 Forbidden`. This
means that the security policy is working as intended: only the admin can change
`eval/secret`, but the `eval/machine` host can fetch it.

---

## Addendum: files and scripts

Using `dev.sh` you can generate all the files and scripts as described in this
guide. It uses the Markdown source of this README and pieces it together to
create the files. That makes this a _literate guide_ in the sense of literate
programming.

###### file:bin/start
```bash
#!/usr/bin/env bash
set -eu

echo -n 'Enter your account: '
read account

set -x

<<Initialize the client>>
```

###### file:bin/load-one-variable-policy
```bash
#!/usr/bin/env bash
set -eux

<<Load a policy>>

```

###### file:bin/load-variable-plus-host-policy
```bash
#!/usr/bin/env bash
set -eux

<<Load variable+host policy>>
```

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
