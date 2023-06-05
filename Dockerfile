# Start with a base image
FROM elixir:1.14.5

# Install software dependencies
RUN apt-get update && \
    apt-get install -y postgresql inotify-tools wget build-essential curl git

# Install PostgreSQL
RUN apt-get update && \
    apt-get install -y postgresql


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
COPY . .


# Expose the PostgreSQL port
EXPOSE 5432

RUN mix local.hex --force

RUN mix local.rebar --force
RUN mix hex.repo 

# Install project dependencies and compile
RUN mix deps.get 

# Run the setup command
RUN mix setup

# Start the Phoenix server
CMD ["iex", "-S", "mix", "phx.server"]
