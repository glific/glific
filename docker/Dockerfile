ARG ELIXIR_VERSION
ARG ERLANG_VERSION
ARG ALPINE_VERSION
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION}

# These two args need to stay here – otherwise they will be empty at RUN stage
ARG NODE_VERSION
ARG POSTGRES_VERSION
ARG FP
ARG AUTH_KEY

ENV LANG=C.UTF-8

# Install dependencies
RUN apk add --no-cache --update \
    build-base git curl zsh vim inotify-tools openssl ncurses-libs npm \
    nodejs-current~${NODE_VERSION} \
    postgresql-client

# Create a directory for the app code
WORKDIR /app/glific

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# configure hex to use oban repo
RUN mix hex.repo add oban https://getoban.pro/repo --fetch-public-key $FP --auth-key $AUTH_KEY

RUN mkdir config


# copy entire config directory
COPY config config

# Copy the dev.secret.exs file
COPY config/dev.secret.exs config/dev.secret.exs

# Copy the .env.dev file
COPY config/.env.dev config/.env.dev

# Copying the code, static files and other required artifacts
COPY priv priv
COPY lib lib
COPY assets assets

# Creating the cert folder to ensure it's existence during mounting
RUN mkdir -p priv/cert


COPY mix.lock mix.exs /app/glific/

RUN mix deps.get
RUN mix deps.compile
    
ENTRYPOINT ["/bin/sh", "/app/glific/config/entrypoint.sh"]
