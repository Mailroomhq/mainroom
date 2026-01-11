defmodule Mailroom.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MailroomWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:mailroom, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mailroom.PubSub},
      {Registry, keys: :unique, name: Mailroom.Queue.Registry},
      Mailroom.Queue.Supervisor,
      Mailroom.Queue.StatsAggregator,
      Mailroom.Consumer.Supervisor,
      Mailroom.Consumer.Manager,
      # Start the Finch HTTP client for sending emails
      {Finch, name: Mailroom.Finch},
      # Start a worker by calling: Mailroom.Worker.start_link(arg)
      # {Mailroom.Worker, arg},
      # Start to serve requests, typically the last entry
      MailroomWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mailroom.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MailroomWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
