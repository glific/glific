# Glific - Two Way Open Source Communication Platform

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

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

## Learn more

### Glific
  * [One Pager](https://docs.google.com/document/d/1XYxNvIYzNyX2Ve99-HrmTC8utyBFaf_Y7NP1dFYxI9Q/edit?usp=sharing)
  * [Google Drive](https://drive.google.com/drive/folders/1aMQvS8xWRnIEtsIkRgLodhDAM-0hg0v1?usp=sharing)
  * [Product Features](https://docs.google.com/document/d/1uUWmvFkPXJ1xVMr2xaBYJztoItnqxBnfqABz5ad6Zl8/edit?usp=sharing)
  * [First Blog Post](https://chintugudiya.org/two-way-communication-project-kickoff/)

## Chat with us

  * [Chat on Discord](https://discord.gg/me6NCMu) - Coming soon
