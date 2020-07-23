FROM elixir:1.10.4-alpine as build
MAINTAINER opensource@coloredcow.com

RUN mkdir /app
WORKDIR /app

# install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force
RUN apk add git

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
# COPY mix.exs mix.lock ./
# COPY config config
COPY . .
RUN HEX_HTTP_CONCURRENCY=1 HEX_HTTP_TIMEOUT=120 mix deps.get --only prod
RUN mix deps.compile

# build project
# COPY priv priv
# COPY lib lib
RUN mix compile

RUN mix release

# prepare release image
FROM alpine:3.9 AS app

# install runtime dependencies
RUN apk add --update bash openssl postgresql-client

EXPOSE 4000
ENV MIX_ENV=prod

# prepare app directory
RUN mkdir /app
WORKDIR /app

# copy release to app container
COPY --from=build /app/_build/prod/rel/prod .
COPY build_scripts/entrypoint.sh .
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
CMD ["bash", "/app/entrypoint.sh"]