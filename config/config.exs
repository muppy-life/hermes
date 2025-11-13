# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :hermes,
  ecto_repos: [Hermes.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure Oban
config :hermes, Oban,
  engine: Oban.Engines.Basic,
  queues: [default: 10, events: 50, media: 20],
  repo: Hermes.Repo

# Configures the endpoint
config :hermes, HermesWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: HermesWeb.ErrorHTML, json: HermesWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Hermes.PubSub,
  live_view: [signing_salt: "q5ODALyt"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :hermes, Hermes.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  hermes: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  hermes: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Gettext for internationalization
config :hermes, HermesWeb.Gettext,
  default_locale: "en",
  locales: ~w(en es)

# Configure Nx to use Binary backend (CPU-only, no compilation needed)
# For better performance, you can later switch to EXLA.Backend after compiling it
config :nx, :default_backend, Nx.BinaryBackend

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
