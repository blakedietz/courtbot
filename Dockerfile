FROM elixir:1.7.3

ARG MIX_ENV=prod
ENV MIX_ENV ${MIX_ENV}

WORKDIR /opt/app

RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install build-essential erlang-dev -y

RUN mix local.rebar --force
RUN mix local.hex --force

COPY . .

RUN mix deps.get
RUN mix deps.compile
RUN mix compile

RUN mix release --env=${MIX_ENV} --verbose \
  && mv _build/${MIX_ENV}/rel/courtbot /opt/release

FROM debian:stretch

ENV LANG en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV REPLACE_OS_VARS true

RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install locales libssl-dev -y
RUN locale-gen en_US.UTF-8
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

WORKDIR /opt/app
COPY --from=0 /opt/release .
CMD trap 'exit' INT; /opt/app/bin/courtbot foreground
