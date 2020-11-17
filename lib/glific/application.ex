defmodule Glific.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      Glific.Vault,
      Glific.Repo,

      # Start the Telemetry supervisor
      GlificWeb.Telemetry,

      # Start the PubSub system
      {Phoenix.PubSub, name: Glific.PubSub},

      # Start the Endpoint (http/https)
      GlificWeb.Endpoint,

      # Start Mnesia to be used for pow cache store
      Pow.Store.Backend.MnesiaCache,
      # Add Oban to process jobs
      {Oban, oban_config()},

      # Add Absinthe's subscription
      {Absinthe.Subscription, GlificWeb.Endpoint},

      # Add Cachex
      %{
        id: :glific_cache_id,
        start: {Cachex, :start_link, [:glific_cache, []]}
      },

      # add poolboy and list of associated worker
      :poolboy.child_spec(message_poolname(), poolboy_config())
    ]

    glific_children = []

    children =
      if Application.get_env(:glific, :environment) == :test,
        do: children,
        else: children ++ glific_children

    # Add this :telemetry.attach/4 call:
    :telemetry.attach(
      "appsignal-ecto",
      [:glific, :repo, :query],
      &Appsignal.Ecto.handle_event/4,
      nil
    )

    :telemetry.attach("oban-failure", [:oban, :job, :exception], &Glific.Appsignal.handle_event/4, nil)
    :telemetry.attach("oban-success", [:oban, :job, :stop], &Glific.Appsignal.handle_event/4, nil)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Glific.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def message_poolname,
    do: :message_pool

  defp poolboy_config do
    opts = Application.get_env(:glific, Poolboy)
    default = Glific.Processor.ConsumerWorker

    worker =
      if is_nil(opts),
        do: default,
        else: Keyword.get(opts, :worker, default)

    [
      name: {:local, message_poolname()},
      worker_module: worker,
      size: 10,
      max_overflow: 10
    ]
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
