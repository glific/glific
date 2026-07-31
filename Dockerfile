ARG ELIXIR_VERSION
ARG ERLANG_VERSION
ARG ALPINE_VERSION

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION}

# These two args need to stay here – otherwise they will be empty at RUN stage
ARG NODE_VERSION
ARG FP=DOES_NOT_EXIST
ARG AUTH_KEY=DOES_NOT_EXIST

ENV LANG=C.UTF-8

# Install dependencies
RUN apk add --no-cache --update \
    build-base git curl zsh vim inotify-tools openssl ncurses-libs npm \
    nodejs~${NODE_VERSION} \
    postgresql15-client \
    postgresql15-dev

# Create a directory for the app code
WORKDIR /app/glific

# Install Hex and Rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# configure hex to use oban repo
RUN mix hex.repo add oban https://getoban.pro/repo --fetch-public-key $FP --auth-key $AUTH_KEY

# Install mkcert
RUN wget -O mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-amd64 && \
    chmod +x mkcert && \
    mv mkcert /usr/local/bin

RUN mkdir config


# copy entire config directory
COPY config config

# Copy the dev.secret.exs file
COPY config/dev.secret.exs.txt config/dev.secret.exs

# Copy the .env.dev file
COPY config/.env.dev.txt config/.env.dev

# Create the priv/cert directory
RUN mkdir -p priv/cert

# Install SSL certificates

RUN /usr/local/bin/mkcert --install && \
    mkcert glific.test api.glific.test && \
    mv glific.test* priv/cert && \
    cp "`mkcert --CAROOT`/"/* priv/cert

COPY mix.lock mix.exs .

# do the setup, break into steps for caching during debugging
RUN mix deps.get
RUN mix deps.compile

# Copy the application source (lib/, priv/, assets/). Required for a standalone
# image build (Bunnyshell/CI) — local docker-compose mounts the source instead.
COPY . .

# Build-time only: runtime.exs is evaluated during `mix compile`, and the baked
# .env.dev sets ENABLE_DB_SSL=true with a bogus CA cert. Force it off so the build
# survives; the container runtime value comes from the deploy env either way.
ENV ENABLE_DB_SSL=false

# Precompile at build time, where the full dep tree is loaded, so compile-time
# guards like `Code.ensure_loaded?(Ecto)` in lib/glific/flags/ecto.ex resolve true
# and the module is actually built. Fail loudly if the guard still drops it.
RUN mix compile
RUN test -f _build/dev/lib/glific/ebin/Elixir.Glific.FunWithFlags.Store.Persistent.Ecto.beam \
    || (echo "BUILD CHECK: Glific.FunWithFlags.Store.Persistent.Ecto beam MISSING after compile" && exit 1)

ENTRYPOINT ["/bin/sh", "/app/glific/config/entrypoint.sh"]
