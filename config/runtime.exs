import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hermes start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hermes, HermesWeb.Endpoint, server: true
end

# AppSignal runtime configuration. Activates only when a push API key is set,
# so dev/test stay inert unless explicitly configured.
if appsignal_key = System.get_env("APPSIGNAL_PUSH_API_KEY") do
  config :appsignal, :config,
    otp_app: :hermes,
    name: System.get_env("APPSIGNAL_APP_NAME") || "hermes",
    push_api_key: appsignal_key,
    env: System.get_env("APPSIGNAL_APP_ENV") || to_string(config_env()),
    revision: System.get_env("APPSIGNAL_APP_REVISION") || System.get_env("GIT_SHA"),
    active: true,
    enable_error_backend: true,
    send_params: true
end

# Configure Claude API key from environment variable
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :hermes, :anthropic_api_key, api_key
end

# Configure GitHub integration from environment variables.
# The HERMES_ prefix avoids GitHub Actions' reserved GITHUB_* namespace
# so the same names can be stored as repository secrets.
config :hermes, :github,
  token: System.get_env("HERMES_GITHUB_TOKEN"),
  owner: System.get_env("HERMES_GITHUB_OWNER"),
  default_repo: System.get_env("HERMES_GITHUB_DEFAULT_REPO"),
  api_url: System.get_env("HERMES_GITHUB_API_URL") || "https://api.github.com",
  graphql_url: System.get_env("HERMES_GITHUB_GRAPHQL_URL") || "https://api.github.com/graphql",
  project_id: System.get_env("HERMES_GITHUB_PROJECT_ID"),
  status_field_id: System.get_env("HERMES_GITHUB_STATUS_FIELD_ID"),
  webhook_secret: System.get_env("HERMES_GITHUB_WEBHOOK_SECRET")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Configure SSL for database connections
  # Vultr managed databases use self-signed certificates
  ssl_opts =
    if System.get_env("DATABASE_SSL") != "false" do
      [ssl: [verify: :verify_none]]
    else
      []
    end

  config :hermes, Hermes.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    ssl: ssl_opts[:ssl] || false

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :hermes, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # Static assets URL (CloudFront CDN)
  static_url = System.get_env("STATIC_URL")

  endpoint_config = [
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base
  ]

  # Add static_url if configured (for CloudFront CDN)
  # STATIC_URL can be a full URL (https://cdn.example.com) or just a host (cdn.example.com)
  endpoint_config =
    if static_url do
      # Extract host from full URL if needed
      static_host =
        case URI.parse(static_url) do
          %URI{host: host} when is_binary(host) -> host
          _ -> static_url
        end

      Keyword.put(endpoint_config, :static_url, host: static_host, scheme: "https", port: 443)
    else
      endpoint_config
    end

  config :hermes, HermesWeb.Endpoint, endpoint_config

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :hermes, HermesWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :hermes, HermesWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # The SendGrid API key is required for sending emails in production.
  # Set the SENDGRID_API_KEY environment variable in your deployment.
  config :hermes, Hermes.Mailer,
    adapter: Swoosh.Adapters.Sendgrid,
    api_key:
      System.get_env("SENDGRID_API_KEY") ||
        raise("environment variable SENDGRID_API_KEY is missing.")

  config :hermes, :s3,
    bucket:
      System.get_env("AWS_S3_BUCKET") ||
        raise("environment variable AWS_S3_BUCKET is missing."),
    host:
      System.get_env("AWS_S3_HOST") ||
        raise("environment variable AWS_S3_HOST is missing."),
    region:
      System.get_env("AWS_S3_REGION") ||
        raise("environment variable AWS_S3_REGION is missing."),
    access_key_id:
      System.get_env("AWS_S3_ACCESS_KEY_ID") ||
        raise("environment variable AWS_S3_ACCESS_KEY_ID is missing."),
    secret_access_key:
      System.get_env("AWS_S3_SECRET_ACCESS_KEY") ||
        raise("environment variable AWS_S3_SECRET_ACCESS_KEY is missing.")

  config :ex_aws,
    access_key_id:
      System.get_env("AWS_ACCESS_KEY_ID") ||
        raise("environment variable AWS_ACCESS_KEY_ID is missing."),
    secret_access_key:
      System.get_env("AWS_SECRET_ACCESS_KEY") ||
        raise("environment variable AWS_SECRET_ACCESS_KEY is missing.")
end
