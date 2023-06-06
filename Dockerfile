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

<<<<<<< Updated upstream
=======
# Install additional dependencies
RUN apt-get update && \
    apt-get install -y wget build-essential

# Install Erlang
RUN wget https://packages.erlang-solutions.com/erlang-solutions_2.0_all.deb && \
    dpkg -i erlang-solutions_2.0_all.deb && \
    apt-get update && \
    apt-get install -y esl-erlang

# Set the working directory
WORKDIR /app.


# Copy the dev.secret.exs file
COPY config/dev.secret.exs.txt config/dev.secret.exs

# Copy the .env.dev file
COPY config/.env.dev.txt config/.env.dev

# Install mkcert
RUN wget -O mkcert https://github.com/FiloSottile/mkcert/releases/download/v1.4.3/mkcert-v1.4.3-linux-amd64 && \
    chmod +x mkcert && \
    mv mkcert /usr/local/bin

# Create the priv/cert directory
RUN mkdir -p priv/cert

# Install SSL certificates
RUN mkcert --install && \
    mkcert glific.test api.glific.test && \
    mv glific.test* priv/cert


 # Copy the application files
>>>>>>> Stashed changes
COPY . .

RUN rm -rf deps/

<<<<<<< Updated upstream
RUN mix do deps.get, setup
=======
# Expose the PostgreSQL port
EXPOSE 5432


# Install the required dependencies
RUN mix local.hex --force
RUN mix local.rebar --force

ARG AUTH_KEY=abcdefghi
ARG FP=xyz

# Add the build argument or environment variable to the mix hex.repo add command
RUN mix hex.repo add oban https://getoban.pro/repo --fetch-public-key $FP --auth-key $AUTH_KEY

# Install project dependencies and compile
RUN mix deps.get 
>>>>>>> Stashed changes

EXPOSE 4000

<<<<<<< Updated upstream
CMD ["mix", "phx.server"]
=======
EXPOSE 4000

# Start the Phoenix server
CMD ["iex", "-S", "mix", "phx.server"]
>>>>>>> Stashed changes
