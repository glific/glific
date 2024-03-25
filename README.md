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

Understanding of middle to advanced level required: It is assumed that you're comfortable using a terminal, installing tools and other dependencies, have git and curl for the backend, and yarn and react for the frontend.

1. Software dependency - Postgres server
2. Software dependency - Erlang / Elixir
3. Backend - Download
4. External service - Gupshup. <-- Get a Free trial to get API-key
5. External service - Oban. <-- Needs 100 Euro per month (patch available to work with free version)
6. Backend - Install certificate
7. Backend - Config
8. Frontend

### 1. Software dependency - Postgres server

- Download and start [postgres server](https://www.postgresql.org/download/)

For Postgres, for the development server, we default to using postgres/postgres/postgres as the username/password/machine name - this is configurable.

We tested and developed against the following versions:

```bash
    - postgres : v13.x, v14.x
```

### 2. Software dependency - Erlang / Elixir

- [Install Elixir](https://elixir-lang.org/install.html#distributions) using asdf (check package versions below)

For Ubuntu users, you also need to install the `inotify-tools` package.

We tested and developed against the following versions (please check .tool-versions in the repository for the latest version we are using):

```bash
    - erlang : 26.1.2
    - elixir : 1.15.7-otp-26
```

After installing the asdf core, install the Erlang and Elixir plugins.

``` bash
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git
```

If you want to install the specific versions that were used for developing and testing:
``` bash
asdf install erlang 26.1.2
asdf install elixir 1.15.7-otp-26
asdf global erlang 26.1.2
asdf global elixir 1.15.7-otp-26
```

If you get any warnings for missing packages, just install them using apt and try again.

**Note**: It is important to use asdf to install Erlang and Elixir.

### 3. Backend - Download

- [Download the latest code from GitHub](https://github.com/glific/glific)

```bash
git clone https://github.com/glific/glific
```

DO NOT run mix deps.get until the next steps are completed.

### 4. External service - Gupshup Create and link your Gupshup Account

[Gupshup](https://www.gupshup.io/developer/home) is an external service that connects to WhatsApp.

You will need to do the following:

- Create a [Gupshup Account](https://www.gupshup.io/developer/home)
- Create an app and select [Access API](https://www.gupshup.io/whatsapp/create-app/access-api)
- You can name it `NewNameHere` "GlificTest <-- Bot Name is already in use, then use another one"
- Run the following command `cp config/dev.secret.exs.txt config/dev.secret.exs` 
- Now, in Gupshup, find your API Key: check the top right corner and click the profile picture or inside the curl sample message
- Enter your APP name and API Key in the dev.secret.exs file using any text editor.

### 5. External service - Oban Pro

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
    oban        https://getoban.pro/repo        SHA256:4/abc/edf/gef+aIWPc   abdedcqweasdj__KEY_AUTH__asdafasdf

If you see two key entries - caused by Oban moving from a public to a private repository - it will fail.
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

### 6. Install certificate - Use SSL for frontend and backend

Before completing the install, you need to create an SSL cert.
Go to the glific_backend folder in the terminal console, and:

- Install mkcert (https://github.com/FiloSottile/mkcert)
- `mkcert --install`
- `mkcert glific.test api.glific.test`
- `mkdir priv/cert`
- `mv glific.test* priv/cert`
- `cd priv/cert`
- `ls -1` Check that glific.test+1-key.pem and glific.test+1.pem exists.
- Check port 4001 `sudo lsof -n -i:4001 | grep LISTEN` should return nothing.
- Check hosts file `grep glific /etc/hosts`

      if it returns nothing, add these 3 lines to the hosts file:
      127.0.0.1 glific.test 
      127.0.0.1 api.glific.test
      127.0.0.1 postgres
      
     

**For Windows the steps is as follows:**

- Install mkcert (https://github.com/FiloSottile/mkcert)
- Run the following command to install the local CA certificates:
  `mkcert --install`
- `mkcert glific.test api.glific.test`
- `mkdir priv/cert`
- `move glific.test* priv/cert`
- `cd priv/cert`
- `dir` Check that glific.test+1-key.pem and glific.test+1.pem exists. 
- Check port 4001 `netstat -ano | findstr :4001` should return nothing.
- Check hosts file by`type %SystemRoot%\System32\drivers\etc\hosts | findstr glific`

      if returns nothing
      add these three lines in your hosts file
      127.0.0.1 glific.test
      127.0.0.1 api.glific.test
      127.0.0.1 postgres

### 7. Backend - Config

- Run: `cp config/.env.dev.txt config/.env.dev`
- Run `mix deps.get`
  if this fails try `mix local.hex --force` followed by `mix deps.get`

  if you see the error below, then your Oban key is wrong or failing. Check step 5 or contact Oban.

  ❯ mix deps.get
  Failed to fetch record for 'hexpm:oban/oban_pro' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  Failed to fetch record for 'hexpm:oban/oban_web' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  \*\* (Mix) Unknown package oban_pro in lockfile

- Run `mix setup`
 At this point, you may get an error saying `password authentication failed for user "postgres"`, in which case, you need to configure the postgres server properly:

```bash
createuser postgres -s # needed for more recent versions of postgres on MacOSgit
sudo -u postgres psql
ALTER USER postgres WITH PASSWORD 'postgres';
```
Exit the PostgreSQL terminal by typing `\q` and pressing Enter. Run `mix setup` again.

- Run `iex -S mix phx.server`
- Inside the iex (you might need to hit enter/return to see the prompt)
  - Update HSM templates by running the following command:
  - `Glific.Templates.sync_hsms_from_bsp(1)`

Now you can visit [`https://glific.test:4001`](https://glific.test:4001) from your browser.



**For Windows the steps is as follows:**

- Copy the file: `cp config/dev.secret.exs.txt config/dev.secret.exs`
- Copy the file: `cp config/.env.dev.txt config/.env.dev`.
  You may not need to edit the default values for DB URL and hostnames in this file if they look suitable for your needs.

- Run this on the command prompt:
  ```
  cd <path-to-glific-backend>
  set /p=DUMMY < config\.env.dev
  ```
  Replace <path-to-glific-backend> with the actual path to the glific_backend directory. This will load the environment variables from the .env.dev file.
- Run `mix deps.get`
  if this fails try `mix local.hex --force` followed by `mix deps.get`

  if you see the error below, then your Oban key is wrong or failing. Check step 5 or contact Oban.

  ❯ mix deps.get
  Failed to fetch record for 'hexpm:oban/oban_pro' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  Failed to fetch record for 'hexpm:oban/oban_web' from registry (using cache instead)
  This could be because the package does not exist, it was spelled incorrectly or you don't have permissions to it
  \*\* (Mix) Unknown package oban_pro in lockfile

- Run `mix setup`
- Run `iex -S mix phx.server`
- Inside the iex (you might need to hit enter/return to see the prompt)
  - Update HSM templates by running the following command:
  - `Glific.Templates.sync_hsms_from_bsp(1)`

Now you can visit [`https://glific.test:4001`](https://glific.test:4001) from your browser.

### 8. Front-end - Install glific front-end

You cannot do much from the glific backend unless you are an API developer. To see Glific in its glory, please
install [Glific Frontend](https://github.com/glific/glific-frontend/)

### Front-end credentials

- Phone `917834811114`
- Password `Secret1234!`

## Optional - Using NGROK

- Install [ngrok](https://ngrok.com/download)
- Start ngrok to proxy port 4000:
  - Start the backend server: `mix phx.server`
  - `$ ngrok http 4000 --host-header=glific.test:4000` (do this in a new window))
  - Remember the URL it assigns you, something like: `https://9f6a7c7822d2.ngrok.io`
- Goto the app settings section, [Dashboard](https://www.gupshup.io/whatsapp/dashboard/?lang=en) -> {{your_appname}} -> Settings.
- On that page, Search for `Manage your Template messaging settings` and enable it
- Goto app webhooks section, [Dashboard](https://www.gupshup.io/whatsapp/dashboard/?lang=en) -> {{your_appname}} -> Webhooks.
- Enter your callback URL that ngrok gave you, add: `/gupshup` to the end. Something like:
  `https://9f6a7c7822d2.ngrok.io/gupshup/`.
- Click `Set`. It should give you a `Callback set successfully` message. If not, check the above steps.
- Save the number `+917834811114` on whatsapp and send a message `PROXY {{your_appname}}`.

## Updating your instance

Run the following commands to update your codebase from the Glific repository.

- Ensure you are in the top-level directory of the Glific API code.
- Get the latest code from master: `git switch master && git pull`
- Ensure you have not modified any files in this directory, by running: `git status`
- Run the setup command: `mix deps.get, compile, ecto.migrate`

## Documentation

- [User Guide](https://docs.glific.com)
- [API docs (Postman) ](https://api.glific.com/)
- [Code Documentation](https://hexdocs.pm/glific/5.1.6/readme.html)
- [Recipes](https://github.com/glific/recipes) - Code samples for some common use cases in Glific.

## Learn more

### Glific

- [Demo Video](https://drive.google.com/file/d/1T8nBKMt1oFndfIHEVlQ38K8lGqjajYaZ/view?usp=sharing)
- [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
- [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
- [Glific Blogs](https://chintugudiya.org/tag/glific/)
- [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)

## Chat with us

- [Chat on Discord](https://discord.gg/me6NCMu)

## Funders

Thanks to our generous funders over the past few years who have funded this project:

- [Project Tech4Dev](https://chintugudiya.org/tech4dev/)
- [The Agency Fund](https://agency.fund/)
- [Cisco](https://www.cisco.com/c/en/us/about/csr.html)
- [Omidyar Network India](https://www.omidyarnetwork.in)
- [FOSS United](https://fossunited.org/)
