defmodule Glific.Providers.Gupshup.V3.Dispatcher do
  @moduledoc """
  Unpacks a Gupshup V3 (Meta format) callback into its entry[].changes[], works out
  each change's type and passes the change's value to the handler registered for it.

  To support a new V3 type, add a module implementing `Glific.Providers.Gupshup.V3.Handler`
  and register it in `@handlers` under the type `change_type/2` returns for it.
  """

  require Logger

  alias Glific.Providers.Gupshup.V3.Handlers.FormResponse
  alias Glific.Providers.Gupshup.V3.Handlers.Status

  @handlers %{
    "statuses" => Status,
    "nfm_reply" => FormResponse
  }

  @doc """
  Handles every change in the entries of a V3 callback
  """
  @spec dispatch(list(), non_neg_integer()) :: :ok
  def dispatch(entries, organization_id) do
    entries
    |> changes()
    |> Enum.each(&dispatch_change(&1, organization_id))
  end

  @spec changes(list()) :: [{String.t() | nil, map()}]
  defp changes(entries) do
    for %{"changes" => changes} when is_list(changes) <- entries,
        %{"value" => %{} = value} = change <- changes,
        do: {change["field"], value}
  end

  @spec dispatch_change({String.t() | nil, map()}, non_neg_integer()) :: :ok
  defp dispatch_change({field, value}, organization_id) do
    type = change_type(field, value)

    case Map.fetch(@handlers, type) do
      {:ok, handler} ->
        handler.handle(value, organization_id)

      :error ->
        Logger.debug("Unhandled Gupshup V3 callback change: field=#{field}, type=#{type}")
    end
  end

  @spec change_type(String.t() | nil, map()) :: String.t() | nil
  defp change_type("messages", %{"statuses" => [_ | _]}), do: "statuses"

  defp change_type("messages", %{"messages" => [%{"interactive" => %{"type" => type}} | _]}),
    do: type

  defp change_type("messages", %{"messages" => [%{"type" => type} | _]}), do: type
  defp change_type(field, _value), do: field
end
