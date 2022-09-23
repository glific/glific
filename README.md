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

## Pre-requisites

There is level of understanding middle to advanced level. It is assumed that you know how to use a terminal, install things and have git; for the backend, and for the frontend use install yarn and react.

1. Software dependency - Postgres server
2. Software dependency - Erlang / Elixir
3. Backend - Download
4. External service - Gupshup. <-- Get a Free trial to get API-key
5. External service - Oban. <-- Needs 100 Euro per month
6. Backend - Install certificate
7. Backend - Config
8. Frontend

### 1. Software dependency - Postgres server

- Download and start [postgres server](https://www.postgresql.org/download/)

For Postgres, for the development server, we default to using postgres/postgres as the username/password. This is configurable

We tested and developed against the following version:

```bash
    - postgres : v13.x
```

### 2. Software dependency - Erlang / Elixir

- [Install Elixir](https://elixir-lang.org/install.html#distributions) (check package versions below)

For Ubuntu users you also need to install the `inotify-tools` package

We tested and developed against the following versions:

```bash
    - erlang : 24.3.4
    - elixir : 1.13.4-otp-24
```

### 3. Backend - Download

- [Download the latest code from GitHub](https://github.com/glific/glific)

```bash
git clone https://github.com/glific/glific
```

DO NOT run mix deps.get until the next steps are completed.

### 4. External service - Gupshup Create and link your Gupshup Account

[Gupshup](https://www.gupshup.io/developer/home) is an external service that connects to WhatsApp

You will need to do the following:

 a. Create a [Gupshup Account](https://www.gupshup.io/developer/home)
 b. Create an app and select [Access API](https://www.gupshup.io/whatsapp/create-app/access-api)
 c. You can name it `NewNameHere` "GlificTest <-- Bot Name is already in use, then use anotherone"
 d. Edit `glific_backend/config/dev.secret.exs`
 e. Find your API Key, check top left corner or inside the curl sample message
 f. Enter your APP name

### 5. External service - Oban Pro

[Oban](https://getoban.pro) is a cron-like library.
Glific depends 100% on job processing.
Oban is **required** before running mix
for Glific to operate.
You **must** purchase license.
When purchashing you must buy WEB+PRO .
After you purchased
Go to account and get this information and run this in glific_backend

```bash
mix hex.repo add oban https://getoban.pro/repo --fetch-public-key SHA256:4/abc/edf/gef+aIWPc --auth-key abdedcqweasdj__KEY_AUTH__asdafasdf
```

Copy the --auth KEY and run this other command

```bash
mix hex.organization auth oban --key abdedcqweasdj__KEY_AUTH__asdafasdf
```

Make sure your key is in the list

```bash
mix hex.repo list
```

    Name        URL                             Public key                                          Auth key
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

If you see it twice, it will not work and fail, since Oban moved from public repository to private
this is how an example of failing looks like

    Name        URL                             Public key                                          Auth key
    hexpm:oban  https://repo.hex.pm/repos/oban  SHA256:abc/edf/gef+aIWPc     abdedcqweasdj__KEY_AUTH__asdafasdf
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

this is wrong, and you run mix deps.get it will try to fetch from public and ignore private and fail
simply remove the public one

```bash
mix hex.repo remove hexpm:oban
```

Now check again

```bash
mix hex.repo list
```

    Name        URL                             Public key                                          Auth key
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

### 6. Install certificate - Use SSL for frontend and backend

Before install also you need to create this SSL cert simila to this
Go to glific_backend folder in the terminal console.

- a. Install mkcert (https://github.com/FiloSottile/mkcert)
- b. `mkcert --install`
- c. `mkcert glific.test api.glific.test`
- d. `mkdir priv/cert`
- e. `mv glific.test* priv/cert`
- f. `cd priv/cert`
- g. `ls -1` Check that glific.test+1-key.pem and glific.test+1.pem exists

      if not then copy any certificate found in there to the correct names
      for example if I see:

```bash
      ❯ ls -1
      glific.test+*-key.pem
      glific.test+*.pem
      glific.test+*-key.pem
      glific.test+*.pem
      ❯ cp glific.test+*-key.pem glific.test+1-key.pem
      ❯ cp glific.test+*.pem glific.test+1.pem
```

      And check again

```bash
      ❯ ls -1
      glific.test+*-key.pem
      glific.test+*.pem
      glific.test+*-key.pem
      glific.test+*.pem
      glific.test+*-key.pem
      glific.test+*.pem
```

- h. Check port 4001 `sudo lsof -n -i:4001 | grep LISTEN` should return nothing.
- i. Check hosts file `grep glific /etc/hosts`

      if returns nothing
      then make sure hosts file has those names added
      `sudo bash -c 'echo "127.0.0.1 glific.test api.glific.test" >> /etc/hosts'`

### 7. Backend - Config

- a. Copy the file: `cp config/dev.secret.exs.txt config/dev.secret.exs` and edit
- b. Copy the file: `cp config/.env.dev.txt config/.env.dev` and edit
- c. Run `source config/.env.dev`
- d. Run `mix deps.get`
  if this fails try first `mix local.hex --force` then `mix deps.get`

  if you see this error, then Oban key is wrong or failing. Check step 5. Or contact Oban.

  ❯ mix deps.get
  Failed to fetch record for 'hexpm:oban/oban_pro' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  Failed to fetch record for 'hexpm:oban/oban_web' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  \*\* (Mix) Unknown package oban_pro in lockfile

- e. Run `mix setup`
- f. Run `mix phx.server`
- g. Another tab of terminal - Start the backend server in iex session: `iex -S mix`
- h. Inside the iex - Update HSM templates: `Glific.Templates.sync_hsms_from_bsp(1)`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

### 8. Frontend - Install glific_frontend

You cannot do much from the glific_backend unless you are an API developer. To see Glific in its glory, please
install [Glific Frontend](https://github.com/glific/glific-frontend/)

```bash
git clone https://github.com/glific/glific_frontend
cd glific_frontend
```

open package.json and update start script

```bash
nano package.json
```

from

    "start": "HTTPS=true SSL_CRT_FILE=../glific/priv/cert/glific.test+1.pem SSL_KEY_FILE=../glific/priv/cert/glific.test+1-key.pem react-scripts start"

to

    "start": "HTTPS=true SSL_CRT_FILE=../glific_backend/priv/cert/glific.test+1.pem SSL_KEY_FILE=../glific_backend/priv/cert/glific.test+1-key.pem react-scripts start"

Copy config file

```bash
cp .env.example .env
```

Make sure the .env config file looks like this

```bash
REACT_APP_API_PREFIX="api"
# localhost
REACT_APP_GLIFIC_API_PORT=4001
REACT_APP_GLIFIC_BACKEND_URL=""
REACT_APP_APPSIGNAL_API_KEY=""
REACT_APP_APPLICATION_NAME="Glific: Two way communication platform"
REACT_APP_LOGFLARE_API_KEY=""
REACT_APP_LOGFLARE_SOURCE_TOKEN=""
REACT_APP_STRIPE_PUBLISH_KEY=""
REACT_APP_RECAPTCHA_CLIENT_KEY="Your recaptch key"
```

USE Double quotes " " , not single ' ' quotes. And do not leave spaces before or after.

Do not use '' for after the = or leave spaces
Broken For example 1

```bash
REACT_APP_GLIFIC_BACKEND_URL='gitflic.test'
```

this will be read like this by react https://%27gitflic.test%27 . notice the %27 which will fail the connection

Broken For example 2

```bash
REACT_APP_GLIFIC_BACKEND_URL= gitflic.test'
```

this will be read like this by react https://%32gitflic.test%27 . notice the %32 which will fail the connection

Broken For example 3

```bash
REACT_APP_GLIFIC_BACKEND_URL="gitflic.test "
```

this will be read like this by react https://gitflic.test%32 . notice the %32 which will fail the connection

Broken For example 4

```bash
REACT_APP_GLIFIC_BACKEND_URL="https://gitflic.test"
```

this will be read like this by react https://https://gitflic.test . notice the extra https:// which will fail the connection

Correct For examples

```bash
REACT_APP_GLIFIC_BACKEND_URL="gitflic.test"
REACT_APP_GLIFIC_BACKEND_URL=gitflic.test
```

Now run install

```bash
yarn setup
```

If there were no failures

```bash
yarn start
```

Go to [`localhost:3000`](http://localhost:3000) from your browser.

### Front end credentials

- Phone `917834811114`
- Password `secret1234`

## Optional - Using NGROK

- Install [ngrok](https://ngrok.com/download)
- Start ngrok to proxy port 4000:
  - Start the backend server: `mix phx.server`
  - `$ ngrok http 4000 --host-header=localhost:4000` (do this in a new window))
  - Remember the URL it assigns you, something like: `https://9f6a7c7822d2.ngrok.io`
- Goto the [Settings Page](https://www.gupshup.io/whatsappassistant/#/settings)
- On that page, Search for `Manage your Template messaging settings` and enable it
- On same page, Search for `Callback URL / Link your Bot`
- Enter your callback URL that ngrok gave you, add: `/gupshup` to the end. Something like:
  `https://9f6a7c7822d2.ngrok.io/gupshup/`
- Click `Set`. It should give you a `Callback set successfully` message. If not, check the above steps.

## Updating your instance

For v0.x releases, we will be resetting the DB and not saving existing state. Run the following commands
to update your codebase from the glific repository.

- Ensure you are in the top level directory of the glific api code.
- Get the latest code from master: `git switch master; git pull`
- Ensure you have not modified any files in this directory, by running: `git status`
- Run the setup command: `mix setup`

## Documentation

- [Postman API docs](https://api.glific.com/)
- [GraphQL API docs](https://glific.github.io/slate/)
- [Code Documentation](https://glific.github.io/glific/doc/readme.html#documentation)
- [User Guide](https://docs.glific.com)
- [Recipes](https://github.com/glific/recipes) - Code smaples for some common use cases in glific.

## Learn more

### Glific

- [Demo Video](https://drive.google.com/file/d/1T8nBKMt1oFndfIHEVlQ38K8lGqjajYaZ/view?usp=sharing)
- [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
- [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
- [Glific Blogs](https://chintugudiya.org/tag/glific/)
- [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)

## Chat with us

- [Chat on Discord](https://discord.gg/me6NCMu)
