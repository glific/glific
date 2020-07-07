# Glific - Two Way Open Source Communication Platform

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)
![](https://github.com/glific/glific/workflows/Continuous%20Integration/badge.svg)
[![Code coverage badge](https://img.shields.io/codecov/c/github/glific/glific/master.svg)](https://codecov.io/gh/glific/glific/branch/master)
[![Glific on hex.pm](https://img.shields.io/hexpm/v/glific.svg)](https://hexdocs.pm/glific/)
![GitHub issues](https://img.shields.io/github/issues-raw/glific/glific)
[![Discord](https://img.shields.io/discord/717975833226248303.svg?label=&logo=discord&logoColor=ffffff&color=7389D8&labelColor=6A7EC2)](https://discord.gg/MVf2KF)

## Packages Needed

Install the following packages using your favorite package manager. Links are provided for some

  * [Install Elixir](https://elixir-lang.org/install.html#distributions)
  * [Install Postgres](https://www.postgresql.org/download/)
    1. For Postgres, for the development server, we default to using postgres/postgres as the username/password.
  This is configurable
    2. The db user needs to have **superuser status** on the database since we create a materialized view.
  This might change in a future release to a table

## Download code

  * [Download the latest code from GitHub](https://github.com/glific/glific)

## Setup
  * Copy the file: `config/dev.secret.exs.txt` to `config/dev.secret.exs` and edit it with your credentials
  * Run `mix setup`
  * Run `mix phx.server`

## Here we go

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Install glific-frontend

You cannot do much from the glific-backend unless you are an API developer. To see Glific in its glory, please
install [Glific Frontend](https://github.com/glific/glific-frontend/)

## Create and link your Gupshup Account

The frontend and backend are great, but you will need an account with a WhatsApp Business Provider to explore the
application. The currently supported backend is [Gupshup](https://www.gupshup.io/developer/home).
You will need to do the following:

  * Create a [Gupshup Account](https://www.gupshup.io/developer/home)
  * Install [ngrok](https://ngrok.com/download)
  * Start ngrok to proxy port 4000: `$ ngrok http 4000` (do this in a new window))
    * Remember the URL it assigns you, something like: `https://9f6a7c7822d2.ngrok.io`
    * Also start the backend server: `mix phx.server` (do this in a new window)
  * Create a [WhatsApp Messaging App on Gupshup](https://www.gupshup.io/whatsappassistant/#/account-setup)
  * You can name it `GlificTest` and ensure the `App Type` is `Access API`
  * Goto the [Settings Page](https://www.gupshup.io/whatsappassistant/#/settings/GlificTest?bt=ACP)
  * On that page, Search for `Callback URL / Link your Bot`
  * Enter your callback URL that ngrok gave you, add: `/gupshup` to the end. Something like:
  `https://9f6a7c7822d2.ngrok.io/gupshup/`
  * Click `Set`. It should give you a `Callback set successfully` message. If not, check the above steps.
  * Edit `config/dev.secret.exs` in the backend directory
  * You will need to enter your API Key, which can be found by clicking on your profile in the top left
  corner of your gupshup dashboard

## Updating your instance

  * Ensure you are in the top level directory of the glific api code.
  * Get the latest code from master: `git switch master; git pull`
  * Run the setup command: `mix setup`

For v0.x releases, we will be resetting the DB and not saving existing state. Run the following commands to push from
## Documentation

  * [Code docs](https://glific.github.io/doc./)
  * [GraphQL API docs](https://glific.github.io/slate/#introduction)

## Learn more

### Glific
  * [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
  * [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)
  * [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
  * [Glific Blogs](https://chintugudiya.org/tag/glific/)

## Chat with us

  * [Chat on Discord](https://discord.gg/me6NCMu)
