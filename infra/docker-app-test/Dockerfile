FROM elixir:1.9.2
ENV MIX_ENV=test
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock /app/
WORKDIR /app
RUN mix deps.get

RUN mix deps.compile

COPY lib /app/lib
COPY test /app/test
RUN mix compile

COPY infra/docker-app-test/start-test.sh /app/
