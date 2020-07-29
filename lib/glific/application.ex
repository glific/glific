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

      # Use Mnesia to store Pow tokens
      {Pow.Store.Backend.MnesiaCache, extra_db_nodes: Node.list()},
      Pow.Store.Backend.MnesiaCache.Unsplit,

      # Add Oban to process jobs
      {Oban, oban_config()},

      # Add Absinthe's subscription
      {Absinthe.Subscription, GlificWeb.Endpoint},

      # Add Cachex
      %{
        id: :glific_cache_id,
        start: {Cachex, :start_link, [:glific_cache, []]}
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
    return_value = Supervisor.start_link(children, opts)

    # not a great spot to put it, but will do for now
    fun_with_flags()

    return_value
  end

  defp fun_with_flags do
    FunWithFlags.enable(:enable_out_of_office)

    # to begin with lets disable the out_of_office hours.
    # We'll let Oban take care of it
    FunWithFlags.disable(:out_of_office_active)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    GlificWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    Application.get_env(:glific, Oban)
  end
end
