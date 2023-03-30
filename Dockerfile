FROM elixir:1.13.4

WORKDIR /opt/glific

RUN apk update && \
  apk upgrade --no-cache && \
  apk add --no-cache \
    nodejs \
    yarn \
    git \
    build-base \
    nss \
    mkcert && \
  mix local.rebar --force && \
  mix local.hex --force && \
  mix hex.repo add oban https://getoban.pro/repo --fetch-public-key ${OBAN_PUBLIC_KEY} --auth-key ${OBAN_AUTH_KEY} && \
  mix hex.organization auth oban --key ${OBAN_AUTH_KEY} && \
  mkcert --install && \
  mkcert glific.test api.glific.test && \
  mkdir priv/cert &&  \
  mv glific.test* priv/cert

COPY . .

RUN rm -rf deps/

RUN mix do deps.get, setup

EXPOSE 4000

CMD ["mix", "phx.server"]
