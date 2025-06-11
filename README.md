# Glific - Two Way Open Source Communication Platform

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![](https://github.com/glific/glific/workflows/Continuous%20Integration/badge.svg)
[![Code coverage badge](https://img.shields.io/codecov/c/github/glific/glific/master.svg)](https://codecov.io/gh/glific/glific/branch/master)
[![Glific on hex.pm](https://img.shields.io/hexpm/v/glific.svg)](https://hexdocs.pm/glific/)
![GitHub issues](https://img.shields.io/github/issues-raw/glific/glific)
[![Discord](https://img.shields.io/discord/717975833226248303.svg?label=&logo=discord&logoColor=ffffff&color=7389D8&labelColor=6A7EC2)](https://discord.gg/MVf2KF)
[![codebeat badge](https://codebeat.co/badges/dd951390-5f51-4c98-bddc-0b618bdb43fd)](https://codebeat.co/projects/github-com-glific-glific-master)
[![Commits](https://img.shields.io/github/commit-activity/m/glific/glific)](https://img.shields.io/github/commit-activity/m/glific/glific)
[![Glific](https://img.shields.io/endpoint?url=https://dashboard.cypress.io/badge/simple/ocex65&style=flat&logo=cypress)](https://dashboard.cypress.io/projects/ocex65/runs)

## Table of Contents

* [Clone Backend Repository](#clone-backend-repository)
* [Pre-requisites](#pre-requisites)
  * [Software Dependencies](#software-dependencies)
    * [Erlang / Elixir](#erlang--elixir)
    * [Postgres](#postgres)
    * [mkcert](#mkcert)
  * [External Services](#external-services)
    * [Gupshup](#gupshup)
    * [Oban](#oban)
* [Installation](#installation)
* [Unit Testing](#unit-testing)
* [Optional - Setup HSM Messaging](#optional---setup-hsm-messaging)
* [Optional - Using NGROK](#optional---using-ngrok)
* [Updating Your Instance](#updating-your-instance)
* [Documentation](#documentation)
* [Learn More](#learn-more)
* [Chat With Us](#chat-with-us)
* [Funders](#funders)

---

## Clone Backend Repository

```bash
git clone https://github.com/glific/glific
```

## Pre-requisites

### Software Dependencies

#### Erlang / Elixir

Install Elixir using `asdf` (check package versions below).
For Ubuntu users, you also need to install the `inotify-tools` package:

```bash
sudo apt install inotify-tools
```

We tested and developed against the following versions (please check `.tool-versions` in the repository for the latest version we are using):

- erlang : 27.3.3
- elixir : 1.18.3-otp-27

After installing the `asdf` core, install the Erlang and Elixir plugins:

```bash
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
```

If you want to install the specific versions that were used for developing and testing:

```bash
asdf install erlang 27.3.3
asdf install elixir 1.18.3-otp-27
asdf global erlang 27.3.3
asdf global elixir 1.18.3-otp-27
```

If you get any warnings for missing packages, just install them using `apt` and try again.

> **Note**: It is important to use `asdf` to install Erlang and Elixir.

#### Postgres

Install from [PostgreSQL official site](https://www.postgresql.org/download/)

Tested with Postgres versions:

* v13.x
* v14.x

####  Install certificate - Use SSL for frontend and backend

Install from [mkcert GitHub repo](https://github.com/FiloSottile/mkcert)

To generate a certificate:

```bash
mkcert --install
mkcert glific.test api.glific.test
mkdir priv/cert
mv glific.test* priv/cert
cd priv/cert
ls -1  # Check that glific.test+1-key.pem and glific.test+1.pem exist
```

Check port 4001:
```bash
sudo lsof -n -i:4001 | grep LISTEN should return nothing.
```

Check `host file`:
```bash
grep glific /etc/hosts
```
If it returns nothing, add these 3 lines to the hosts file:
```
127.0.0.1 glific.test
127.0.0.1 api.glific.test
127.0.0.1 postgres
```
For Windows the steps is as Follows:

```bash
mkcert --install
mkcert glific.test api.glific.test
mkdir priv/cert
mv glific.test* priv/cert
cd priv/cert
dir # Check that glific.test+1-key.pem and glific.test+1.pem exist
```

Check port 4001:
```bash
netstat -ano | findstr :4001 should return nothing.
```

Check `host file by type`:
```bash
%SystemRoot%\System32\drivers\etc\hosts | findstr glific
```
If it returns nothing, add these 3 lines to the hosts file:
```
127.0.0.1 glific.test
127.0.0.1 api.glific.test
127.0.0.1 postgres
```
### External Services

#### Gupshup

* Register: [Gupshup Developer](https://www.gupshup.io/developer/home)
* Create an app and select Access API
* You can name it NewNameHere "GlificTest <-- Bot Name is already in use, then use another one"
* Run the following command cp config/dev.secret.exs.txt config/dev.secret.exs
* Now, in Gupshup, find your API Key: check the top right corner and click the profile picture or inside the curl sample message
* Enter your APP name and API Key in the dev.secret.exs file using any text editor.

#### Oban

[Oban](https://getoban.pro) is a cron-like library. Glific depends 100% on job processing.
Oban is **required** before running mix for Glific to operate.

**For contributors on social impact projects (including NGOs):**
Please get in touch with the team on Discord and get a limited-time key. Once they're provided to you, run: 

**For others, if you want to use the free Oban solution**
People have created and contributed versions of the code to allow Glific to work with the free version of Oban: https://github.com/glific/glific/pull/2391

```bash
mix hex.repo add oban https://getoban.pro/repo --fetch-public-key SHA256:4/abc/edf/gef+aIWPc --auth-key abcdefghi
```

with your keys

**For production use:**
You must purchase a license.
When purchasing, you must buy WEB+PRO.
After purchasing,
Go to account and run this command in glific_backend:

```bash
mix hex.repo add oban https://getoban.pro/repo --fetch-public-key SHA256:4/abc/edf/gef+aIWPc --auth-key abcdefghi
```

where public key "SHA256:4/abc/edf/gef+aIWPc" is replaced by your public key and auth key "abcdefghi" is replaced by your auth key.

Make sure your key is in the list:

```bash
mix hex.repo list
```

    Name        URL                             Public key                                          Auth key
    hexpm       https://repo.hex.pm             SHA256:abc/edf/gef+aIWPc    
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

If you see two Auth key entries - caused by Oban moving from a public to a private repository - it will fail.
This is what an example of failing looks like:

    Name        URL                             Public key                                          Auth key
    hexpm:oban  https://repo.hex.pm/repos/oban  SHA256:abc/edf/gef+aIWPc     abdedcqweasdj__KEY_AUTH__asdafasdf
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

This is wrong. When you run mix deps.get as is, it will try to fetch from the public repository instead of the private one and fail.
Simply follow the instructions below to remove the public key:

```bash
mix hex.repo remove hexpm:oban
```

Now, check again:

```bash
mix hex.repo list
```

    Name        URL                             Public key                                          Auth key
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

Install frontend: [Glific Frontend Repo](https://github.com/glific/glific-frontend)

### Frontend credentials

* Phone: `917834811114`
* Password: `Secret1234!`

## Unit Testing

```bash
mix test_full
```

## Optional - Setup HSM Messaging

* Add ISV credentials in the database
* Sync HSMs:

```elixir
Glific.Templates.sync_hsms_from_bsp(1)
```

## Optional - Using NGROK

* Download: [ngrok](https://ngrok.com/download)
* Run:

```bash
ngrok http 4000 --host-header=glific.test:4000
```

* Set webhook in Gupshup app settings to `https://<ngrok-url>/gupshup`

## Updating Your Instance
Run the following commands to update your codebase from the Glific repository.
```bash
* Ensure you are in the top-level directory of the Glific API code.
* Get the latest code from master: git switch master && git pull
* Ensure you have not modified any files in this directory, by running: git status
* Run the setup command: mix deps.get, compile, ecto.migrate
```

## Documentation

* [User Guide](https://docs.glific.com)
* [API docs](https://api.glific.com/)
* [Code Documentation](https://hexdocs.pm/glific/5.1.6/readme.html)
* [Recipes](https://github.com/glific/recipes)

## Learn More

* [Demo Video](https://drive.google.com/file/d/1T8nBKMt1oFndfIHEVlQ38K8lGqjajYaZ/view?usp=sharing)
* [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
* [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
* [Glific Blogs](https://chintugudiya.org/tag/glific/)
* [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)

## Chat With Us

* [Join Discord](https://discord.gg/me6NCMu)

## Funders

Thanks to our funders for supporting Glific:

* [Project Tech4Dev](https://chintugudiya.org/tech4dev/)
* [The Agency Fund](https://agency.fund/)
* [Cisco](https://www.cisco.com/c/en/us/about/csr.html)
* [Omidyar Network India](https://www.omidyarnetwork.in)
* [FOSS United](https://fossunited.org/)
