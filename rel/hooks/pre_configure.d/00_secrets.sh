#!/usr/bin/env bash

# Generate our secrets
SECRET_KEY_BASE=$(tr -dc 'A-F0-9' < /dev/urandom | head -c64)
VAULT_KEY=$(tr -dc 'A-F0-9' < /dev/urandom | head -c32 | base64)

# If we don't have a secrets file, then make one.
[ ! -f ${RELEASE_ROOT_DIR}/etc/courtbot.secrets.exs ] && cat > ${RELEASE_ROOT_DIR}/etc/courtbot.secrets.exs <<EOL
use Mix.Config

config :excourtbot, ExCourtbotWeb.Endpoint,
  secret_key_base: "$SECRET_KEY_BASE"

config :excourtbot, ExCourtbot.Vault,
  ciphers: [
    default:
      {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("$VAULT_KEY")}
  ]
EOL
