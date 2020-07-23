defmodule Glific.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Glific.Repo,
      # Start the Telemetry supervisor
      GlificWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Glific.PubSub},
      # Start the Endpoint (http/https)
      GlificWeb.Endpoint,
      {Pow.Store.Backend.MnesiaCache, extra_db_nodes: Node.list()},
      Pow.Store.Backend.MnesiaCache.Unsplit,

      # Add Oban to process jobs
      {Oban, oban_config()},

      # Add Absinthe's subscription
      {Absinthe.Subscription, GlificWeb.Endpoint},

      # Add Cachex
      %{
        id: :flows_cache_id,
        start: {Cachex, :start_link, [:flows_cache, []]}
      }
    ]

    glific_children = [
      Glific.Processor.Producer,
      Glific.Processor.ConsumerTagger
    ]

    children =
      if Application.get_env(:glific, :environment) == :test,
        do: children,
        else: children ++ glific_children

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Glific.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    GlificWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    opts = Application.get_env(:glific, Oban)

    # Prevent running queues or scheduling jobs from an iex console, i.e. when starting app with `iex -S mix`
    if Code.ensure_loaded?(IEx) and IEx.started?() do
      opts
      |> Keyword.put(:crontab, false)
      |> Keyword.put(:queues, false)
    else
      opts
    end
  end
end
