defmodule Glific.BigQuery.SyncError do
  @moduledoc """
  Raised or reported when syncing data to BigQuery fails, so AppSignal groups every sync
  failure under one exception class instead of a generic `ErlangError`.
  """
  defexception [:message]
end
