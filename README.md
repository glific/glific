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

* [Pre-requisites](#1-pre-requisites)
   * [Software Dependencies](#software-dependencies)
     * [Erlang / Elixir](#erlang--elixir)
     * [Postgres](#postgres)
     * [mkcert](#3-install-certificate---use-ssl-for-frontend-and-backend)
* [External Services](#4-external-services)
   * [Gupshup](#gupshup)
   * [Oban](#oban)
* [Clone Backend Repository](#2-clone-backend-repository)
* [Install Frontend](#6-install-frontend)
* [Unit Testing](#8-unit-testing)
* [Optional - Setup HSM Messaging](#optional---setup-hsm-messaging)
* [Optional - Using NGROK](#optional---using-ngrok)
* [Updating Your Instance](#updating-your-instance)
* [Documentation](#documentation)
* [Learn More](#learn-more)
* [Chat With Us](#chat-with-us)
* [Funders](#funders)

---

## 1. Pre-requisites

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

Install all required versions listed in `.tool-versions` by
```bash
asdf install
```

If you get any warnings for missing packages, just install them using `apt` and try again.

> **Note**: It is important to use `asdf` to install Erlang and Elixir.

> **Note**: Windows users should use WSL (Windows Subsystem for Linux) to install and manage Elixir and Erlang via asdf

#### Postgres

Install from [PostgreSQL official site](https://www.postgresql.org/download/)

Tested with Postgres versions:

* v13.x
* v14.x
* v17.x

## 2. Clone Backend Repository

```bash
git clone git@github.com:glific/glific.git
```

## 3. Install certificate - Use SSL for frontend and backend

Before completing the install, you need to create an SSL cert. Go to the glific folder in the terminal console, and:
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
sudo lsof -n -i:4001 | grep LISTEN
```
should return nothing.

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
### For Windows, the steps is are as Follows:

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
netstat -ano | findstr :4001
```
should return nothing.

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
## 4. External Services

### Gupshup
Gupshup is a messaging platform that enables bots and businesses to communicate with users over WhatsApp and other channels. In Glific, we use Gupshup to send and receive WhatsApp messages via API integration.

 * Register: [Gupshup Developer](https://www.gupshup.io/developer/home)
 * Create an app and select Access API
 * You can name it NewNameHere "GlificTest <-- Bot Name is already in use, then use another one"
 * Run the following command cp config/dev.secret.exs.txt config/dev.secret.exs
 * Now, in Gupshup, find your API Key: check the top right corner and click the profile picture or inside the curl sample message
 * Enter your APP name and API Key in the dev.secret.exs file using any text editor.

### Oban

 [Oban](https://getoban.pro) is a job processing library for Elixir. It supports features like background jobs and scheduled tasks (cron-style).
 Oban is **required** before running mix for Glific to operate.

 **For contributors on social impact projects (including NGOs):**

  Please get in touch with the team on Discord and request a limited-time Oban Pro key.
  Once provided, run the following command to add the Oban repository with your credentials:
   ```bash
  mix hex.repo add oban https://getoban.pro/repo --fetch-public-key SHA256:4/abc/edf/gef+aIWPc --auth-key abcdefghi
   ```

 **For others, if you want to use the free Oban solution**
 People have contributed code changes to allow Glific to work with the free version of Oban. You can view the details here: https://github.com/glific/glific/pull/2391

 **For production use:**

  *You must purchase a license for Oban Pro to use advanced features in production.

  *Note: Oban Web is now open source and does not require a license.

  *If you're using Oban Pro, after purchasing the license:


   Go to your Oban account dashboard.

   Run the following command inside your glific_backend directory:

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

### 5. Backend - Config

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
 createuser postgres -s # needed for more recent versions of postgres on MacOS
 sudo -u postgres psql
 ALTER USER postgres WITH PASSWORD 'postgres';
 ```
 Exit the PostgreSQL terminal by typing `\q` and pressing Enter.

#### Setting up SSL for Postgres (Optional but recommended)

 To enable SSL connections to Postgres:

 1. Find your Postgres data directory:
 ```bash
 psql -U postgres -c "SHOW data_directory;"
 ```

 2. Create SSL certificates using mkcert:
 ```bash
 mkcert -cert-file server.crt -key-file server.key postgres localhost 127.0.0.1 ::1
 ```

 3. Copy the certificates to Postgres data directory:
 ```bash
 sudo cp server.crt /path/to/postgres/data/directory/
 sudo cp server.key /path/to/postgres/data/directory/
 sudo chmod 600 /path/to/postgres/data/directory/server.key
 ```

 4. Configure Postgres to use SSL. Edit postgresql.conf:
 ```bash
 sudo nano /path/to/postgres/data/directory/postgresql.conf
 ```
 Add:
 ```conf
 ssl = on
 ssl_cert_file = 'server.crt'
 ssl_key_file = 'server.key'
 ```

 5. Configure client authentication. Edit pg_hba.conf:
 ```bash
 sudo nano /path/to/postgres/data/directory/pg_hba.conf
 ```
 Add:
 ```conf
 hostssl glific_dev      all             127.0.0.1/32            trust
 hostssl glific_test     all             127.0.0.1/32            trust
 hostssl postgres        all             127.0.0.1/32            trust
 ```

 6. Restart Postgres:
 ```bash
 # For Linux:
 sudo systemctl restart postgresql
 # For MacOS:
 brew services restart postgresql
 # For MacOS, if you installed Postgres with Postgres.app, quit and run Postgres.app
 ```

 7. Setup CA certificates for Glific:
 ```bash
 CAROOT=$(mkcert -CAROOT)
 cp "$CAROOT/rootCA.pem" priv/cert/glific-CA.pem
 ```

 8. Test SSL connection:
 ```bash
 psql "sslmode=require dbname=glific_dev host=localhost"
 ```
 You should see SSL connection details. Verify with:
 ```sql
 SHOW ssl;
 SELECT * FROM pg_stat_ssl WHERE pid=pg_backend_pid();
 ```

 Run `mix setup` again.

 - Run `iex -S mix phx.server`

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

## 6. Install Frontend
  [Glific Frontend Repo](https://github.com/glific/glific-frontend)

### Frontend credentials

 * Phone: `917834811114`
 * Password: `Secret1234!`
## 7. Sync Gupshup Settings
  After setting up both backend and frontend repositories, you need to sync the Gupshup settings:
   - Login to the frontend using the credentials provided above
   - Go to Settings -> Gupshup Settings
   - Click on "Save" button
   - Wait for confirmation that settings were synced successfully.

  This step is crucial as it fetches and stores your Gupshup `app_id` in the database, which is required for proper functioning of various APIs including the wallet API.



## 8. Unit Testing
  Execute All Tests with:
 ```bash
 mix test_full
 ```
  To run Specific test File
  ```bash
 mix test Path_to_the_specific_test_file_you_want_to_run.
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

### Updating Your Instance
 Run the following commands to update your codebase from the Glific repository.
 ```bash
 * Ensure you are in the top-level directory of the Glific API code.
 * Get the latest code from master: git switch master && git pull
 * Ensure you have not modified any files in this directory, by running: git status
 * Run the setup command: mix deps.get, compile, ecto.migrate
 ```

### Documentation

 * [User Guide](https://docs.glific.com)
 * [API docs](https://api.glific.com/)
 * [Code Documentation](https://hexdocs.pm/glific/5.1.6/readme.html)
 * [Recipes](https://github.com/glific/recipes)

### Learn More

 * [Demo Video](https://drive.google.com/file/d/1T8nBKMt1oFndfIHEVlQ38K8lGqjajYaZ/view?usp=sharing)
 * [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
 * [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
 * [Glific Blogs](https://chintugudiya.org/tag/glific/)
 * [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)

### Chat With Us

 * [Join Discord](https://discord.gg/me6NCMu)

### Funders

 Thanks to our funders for supporting Glific:

 * [Project Tech4Dev](https://chintugudiya.org/tech4dev/)
 * [The Agency Fund](https://agency.fund/)
 * [Cisco](https://www.cisco.com/c/en/us/about/csr.html)
 * [Omidyar Network India](https://www.omidyarnetwork.in)
 * [FOSS United](https://fossunited.org/)
