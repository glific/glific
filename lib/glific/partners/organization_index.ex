defmodule Glific.Partners.OrganizationIndex do
  @moduledoc """
  An in-memory map of every organization's shortcode to its id and status.

  Tenant resolution runs on every request, including unauthenticated ones, and used to reach the
  database for any host it did not recognise: `Glific.Partners.organization/1` would fall through
  to `load_cache/1` and query. A miss is never cached, so URL-scan traffic and requests on a
  spoofed `Host` cost one query each, forever.

  This index is the cheap half of the organization cache. It is a single `select` over
  `organizations`, loaded at application start and refreshed every minute, so an unknown host is
  rejected from memory. The expensive half — the full `%Organization{}` that `fill_cache/1` builds
  from around twenty-five queries and flag lookups — stays lazily loaded, but is now only ever
  built for a shortcode that appears here.

  `Glific.Partners.remove_organization_cache/2` refreshes the index as well, so an authenticated
  change to an organization's shortcode or status takes effect without waiting for the next tick.
  `do_update_org/2` refreshes again after its write, because its bust runs before the update.

  Both the index and its timer are node-local, so on more than one node a shortcode renamed on one
  node resolves to nothing on the others until their next tick.

  `refresh/0` is a plain function rather than a `GenServer` call so that it runs in the caller's
  process, which keeps it inside the Ecto sandbox ownership in tests.
  """

  use GenServer

  alias __MODULE__

  import Ecto.Query

  alias Glific.{Caches, Partners.Organization, Repo}

  @cache_key :organization_index
  @refresh_interval :timer.minutes(1)
  @ttl_hours 24

  @type entry :: %{id: non_neg_integer(), status: atom()}

  @doc false
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(OrganizationIndex, opts, name: OrganizationIndex)

  @doc false
  @impl GenServer
  @spec init(any()) :: {:ok, map()} | {:ok, map(), {:continue, :refresh}}
  def init(_opts) do
    if test_env?(),
      do: {:ok, %{}},
      else: {:ok, %{}, {:continue, :refresh}}
  end

  @doc false
  @impl GenServer
  def handle_continue(:refresh, state) do
    refresh()
    schedule_refresh()
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info(:refresh, state) do
    refresh()
    schedule_refresh()
    {:noreply, state}
  end

  # Defining handle_info/2 at all replaces the catch-all `use GenServer` provides, and a stray
  # message — a timer surviving a restart, a late :DOWN — would otherwise kill the process.
  def handle_info(_message, state), do: {:noreply, state}

  @doc """
  Look up an organization id by shortcode, without touching the database.

  Returns `:error` when the shortcode is not a known organization, and `:unavailable` when the
  index has not been loaded yet, which lets the caller fall back for the short window between the
  endpoint accepting requests and the first load completing.
  """
  @spec fetch(String.t()) :: {:ok, non_neg_integer()} | :error | :unavailable
  def fetch(shortcode) do
    case Caches.get_global(@cache_key) do
      {:ok, index} when is_map(index) -> lookup(index, shortcode)
      _not_loaded -> :unavailable
    end
  end

  @doc """
  Reload the index after an organization changed.

  `config/test.exs` turns this off, because the index lives in Cachex rather than in the Ecto
  sandbox: an index built inside a test's transaction would outlive that transaction's rollback
  and resolve tenants wrongly for every test that follows. A test that wants the production
  behaviour turns `:refresh_organization_index` back on for its duration.
  """
  @spec refresh_on_change :: map() | :ok
  def refresh_on_change do
    if Application.get_env(:glific, :refresh_organization_index, true), do: refresh(), else: :ok
  end

  @doc """
  Reload the index from the database and publish it to the cache.
  """
  @spec refresh :: map()
  def refresh do
    Organization
    |> select([organization], {organization.shortcode, organization.id, organization.status})
    |> Repo.all(skip_organization_id: true)
    |> Map.new(fn {shortcode, id, status} -> {shortcode, %{id: id, status: status}} end)
    |> publish()
  rescue
    error -> failed_refresh(error)
  catch
    :exit, reason -> failed_refresh(reason)
  end

  # An empty result would be cached as a loaded index and resolve every host to :error. Leaving it
  # unpublished keeps the previous index, or falls back to the database if there is none.
  @spec publish(map()) :: map()
  defp publish(index) when map_size(index) == 0, do: index

  defp publish(index) do
    Caches.put_global(@cache_key, index, @ttl_hours)
    index
  end

  # log_error/1 rather than log_exception/1: the latter drops anything whose :message is not a
  # binary, which would make a persistently failing refresh completely silent.
  @spec failed_refresh(any()) :: map()
  defp failed_refresh(error) do
    Glific.log_error(
      "Could not refresh the organization index: #{Glific.SafeLog.safe_inspect(error)}"
    )

    %{}
  end

  @spec lookup(map(), String.t()) :: {:ok, non_neg_integer()} | :error
  defp lookup(index, shortcode) do
    with %{id: id, status: status} <- Map.get(index, shortcode),
         :active <- Glific.safe_string_to_atom(status) do
      {:ok, id}
    else
      _inactive_or_unknown -> :error
    end
  end

  @spec schedule_refresh :: reference()
  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  @spec test_env? :: boolean()
  defp test_env?, do: Application.get_env(:glific, :environment) == :test
end
