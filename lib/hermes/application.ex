defmodule Hermes.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    attach_appsignal_logger()

    children =
      [
        HermesWeb.Telemetry,
        Hermes.Repo,
        {Oban, Application.fetch_env!(:hermes, Oban)},
        {DNSCluster, query: Application.get_env(:hermes, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Hermes.PubSub},
        HermesWeb.Presence,
        Hermes.Requests.DraftStore
      ] ++
        github_in_memory_child() ++
        [
          # Start to serve requests, typically the last entry
          HermesWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hermes.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Trigger background model loading after app starts
    schedule_model_loading()

    result
  end

  defp github_in_memory_child do
    if Application.get_env(:hermes, :github_adapter) == Hermes.Services.GitHub.InMemory do
      [Hermes.Services.GitHub.InMemory]
    else
      []
    end
  end

  # Forward Elixir Logger events (warning+) and SASL crash reports to AppSignal.
  # No-op unless AppSignal is active (APPSIGNAL_PUSH_API_KEY set).
  defp attach_appsignal_logger do
    if Appsignal.Config.active?() do
      :ok = Appsignal.Logger.Handler.add("hermes")
    end
  rescue
    # Never block boot on instrumentation failures.
    _ -> :ok
  end

  defp schedule_model_loading do
    # Schedule model loading job to run immediately in the background for production environments
    if Application.get_env(:hermes, :env) == :prod do
      %{}
      |> Hermes.Workers.ModelLoaderWorker.new(queue: :media)
      |> Oban.insert()
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HermesWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
