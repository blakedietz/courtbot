FROM elixir:1.7.4 as build

ARG MIX_ENV=prod
ENV MIX_ENV ${MIX_ENV}

WORKDIR /opt/app

RUN curl -sL https://deb.nodesource.com/setup_11.x | bash -
RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install build-essential erlang-dev nodejs -y

RUN mix local.rebar --force
RUN mix local.hex --force

COPY mix.exs .
COPY mix.lock .

RUN mkdir assets

COPY assets/package.json assets/
COPY assets/package-lock.json assets/

RUN mix deps.get
RUN mix deps.compile

RUN cd assets \
  && npm install \
  && cd ..

COPY . .

RUN mix compile

RUN cd assets \
  && npm run build \
  && npm run webpack:production \
  && cd ..

RUN mix phx.digest

RUN mix release --env=${MIX_ENV} --verbose \
  && mv _build/${MIX_ENV}/rel/courtbot /opt/release

FROM debian:stretch as runtime

ENV LANG en_US.UTF-8
ENV LC_CTYPE en_US.UTF-8
ENV LC_ALL en_US.UTF-8
ENV REPLACE_OS_VARS true

RUN apt-get update -y && apt-get upgrade -y
RUN apt-get install locales libssl-dev -y
RUN locale-gen en_US.UTF-8
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

WORKDIR /opt/app
COPY --from=build /opt/release .
CMD trap 'exit' INT; /opt/app/bin/courtbot foreground
