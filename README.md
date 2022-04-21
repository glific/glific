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

## Packages Needed

Install the following packages using your favorite package manager. Links are provided for some

- [Install Elixir](https://elixir-lang.org/install.html#distributions) (check package versions below)
  1. For Ubuntu users you also need to install the `inotify-tools` package
- [Install Postgres](https://www.postgresql.org/download/)
  1. For Postgres, for the development server, we default to using postgres/postgres as the username/password. This is configurable

## Package Versions

Glific is currently developed and hosted on the following platforms. Our goal is to always try
and use the latest versions of each platform as soon as feasible (i.e. once the ecosystem
of packages we used have upgraded). We do not have the bandwidth to support earlier versions
of the packages.

- erlang : 24.2.2
- elixir : 1.13.3-otp-24
- postgres : v13.x

## Download code

- [Download the latest code from GitHub](https://github.com/glific/glific)

## Pre-requisites

### Oban Pro

Used for robust job processing and is **required** for Glific setup. You can purchase license [here](https://getoban.pro) and get your set of `OBAN_PRO_KEY`.

## Setup

- Copy the file: `config/dev.secret.exs.txt` to `config/dev.secret.exs` and edit it with your credentials
- Copy the file: `config/.env.dev.txt` to `config/.env.dev` and edit it with your credentials
- Run `source config/.env.dev`
- Start the postgres server
- Run `mix hex.organization auth oban --key {OBAN_PRO_KEY}`
- Run `mix setup`
- This will setup Glific with default credentials as:
  - Phone `917834811114`
  - Password `secret1234`
- Run `mix phx.server`

## Here we go

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Install glific-frontend

You cannot do much from the glific-backend unless you are an API developer. To see Glific in its glory, please
install [Glific Frontend](https://github.com/glific/glific-frontend/)

## Create and link your Gupshup Account

The frontend and backend are great, but you will need an account with a WhatsApp Business Provider to explore the
application. The currently supported backend is [Gupshup](https://www.gupshup.io/developer/home).
You will need to do the following:

- Create a [Gupshup Account](https://www.gupshup.io/developer/home)
- Create a [WhatsApp Messaging App on Gupshup](https://www.gupshup.io/whatsappassistant/#/account-setup)
- You can name it `GlificTest` and ensure the `App Type` is `Access API`
- Edit `config/dev.secret.exs` in the backend directory
- Enter your API Key, which can be found by clicking on your profile in the top left
  corner of your gupshup dashboard
- Enter your APP name
- Start the backend server in iex session: `iex -S mix`
- Update HSM templates: `Glific.Templates.sync_hsms_from_bsp(1)`
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

## Use SSL for frontend and backend

(we'll be making the switch to using SSL for both frontend and backend in development post 1.5).
These are the preliminary steps involved

- Install mkcert (https://github.com/FiloSottile/mkcert)
- `mkcert --install`
- `mkcert glific.test api.glific.test`
- `mkdir priv/cert`
- `mv glific.test+1* priv/cert`
- The backend config files for development will assume that the port is 4001 with the above hostnames
- Switch the frontend to use https port 4001 for the backend

## Documentation

- [Postman API docs](https://postman.glific.com/)
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
