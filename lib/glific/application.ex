defmodule Glific.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Glific.Communications.Mailer

  def start(_type, _args) do
    children = [
      # Start the vault server before ecto
      Glific.Vault,

      # Start the Ecto repository
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
      :poolboy.child_spec(message_poolname(), poolboy_config()),

      # Add the flow metrics caching code
      Glific.Metrics,

      # Add the process to manage simulator contacts and flows
      Glific.State,

      # Add the broadcast task supervisor
      {Task.Supervisor, name: Glific.Broadcast.Supervisor}
    ]

    # Add this :telemetry.attach/4 for oban success/failure call:
    attach_oban_telemetry_event()

    # Add this :telemetry.attach/4 for swoosh success/failure call:
    attach_mailer_telemetry_event()

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
      max_overflow: 10,
      # we are using the fifo strategy, so the state of all the consumer workers
      # are filled when the load gets high
      strategy: :fifo
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    GlificWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp oban_config do
    opts = Application.get_env(:glific, Oban)

    if in_console?() do
      opts
      |> Keyword.put(:plugins, false)
      |> Keyword.put(:queues, false)
    else
      opts
    end
  end

  defp in_console? do
    Code.ensure_loaded?(IEx) && IEx.started?()
  end

  defp attach_oban_telemetry_event do
    :telemetry.attach(
      "oban-success",
      [:oban, :job, :stop],
      &Glific.Appsignal.handle_event/4,
      []
    )

    :telemetry.attach(
      "oban-failure",
      [:oban, :job, :exception],
      &Glific.Appsignal.handle_event/4,
      []
    )

    :telemetry.attach(
      "oban-plugin-success",
      [:oban, :plugin, :stop],
      &Glific.Appsignal.handle_event/4,
      []
    )

    :telemetry.attach(
      "oban-plugin-failure",
      [:oban, :plugin, :exception],
      &Glific.Appsignal.handle_event/4,
      []
    )
  end

  defp attach_mailer_telemetry_event do
    :telemetry.attach_many(
      "mailer-event-handler",
      [
        [:swoosh, :deliver, :stop],
        [:swoosh, :deliver, :exception],
        [:swoosh, :deliver_many, :stop],
        [:swoosh, :deliver_many, :exception]
      ],
      &Mailer.handle_event/4,
      nil
    )
  end
end
