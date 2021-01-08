defmodule GlificWeb.Resolvers.WebhookLogs do
  @moduledoc """
  WebhookLog Resolver which sits between the GraphQL schema and Glific WebhookLog Context API. This layer basically stiches together
  one or more calls to resolve the incoming queries.
  """

  alias Glific.{
    Flows.WebhookLog,
    Repo
  }

  @doc """
  Get the list of webhook_logs filtered by args
  """
  @spec webhook_logs(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, [WebhookLog]}
  def webhook_logs(_, args, _) do
    {:ok, Repo.list_filter(args, WebhookLog, &Repo.opts_with_nil/2, &Repo.filter_with/2)}
  end

  @doc """
  Get the count of webhook_logs filtered by args
  """
  @spec count_webhook_logs(Absinthe.Resolution.t(), map(), %{context: map()}) :: {:ok, integer}
  def count_webhook_logs(_, args, _) do
    {:ok, WebhookLog.count_webhook_logs(args)}
  end
end
