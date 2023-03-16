FROM elixir:latest

WORKDIR /opt/glific


COPY . .

RUN apt update
# RUN apt install nodejs
RUN apt-get install git
# RUN apt install libnss3-tools -y
# RUN curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
# RUN chmod +x mkcert-v*-linux-amd64
# RUN cp mkcert-v*-linux-amd64 /usr/local/bin/mkcert
# RUN mkcert --install && \
#   mkcert glific.test api.glific.test && \
#   # mkdir priv/cert &&  \
#   mv glific.test* priv/cert


RUN mix local.rebar --force
RUN mix local.hex --force

RUN mix hex.repo add oban https://getoban.pro/repo --fetch-public-key SHA256:4/OSKi0NRF91QVVXlGAhb/BIMLnK8NHcx/EWs+aIWPc --auth-key ************************
RUN mix hex.organization auth oban --key ************************


RUN rm -rf deps/

RUN HEX_HTTP_TIMEOUT=120 mix deps.get


RUN mix setup

EXPOSE 4000

CMD ["mix", "phx.server"]