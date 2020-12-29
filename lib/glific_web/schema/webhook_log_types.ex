defmodule GlificWeb.Schema.WebhookLogTypes do
  @moduledoc """
  GraphQL Representation of Glific's WebhookLog DataType
  """
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias Glific.Repo
  alias GlificWeb.Resolvers
  alias GlificWeb.Schema.Middleware.Authorize

  object :webhook_log_result do
    field :webhook_log, :webhook_log
    field :errors, list_of(:input_error)
  end

  object :webhook_log do
    field :id, :id
    field :url, :string
    field :method, :string
    field :request_headers, :json
    field :request_json, :json

    field :response_json, :json
    field :status_code, :integer

    field :error, :string

    field :inserted_at, :datetime
    field :updated_at, :datetime

    field :flow, :flow do
      resolve(dataloader(Repo))
    end

    field :contact, :contact do
      resolve(dataloader(Repo))
    end
  end

  @desc "Filtering options for webhook_logs"
  input_object :webhook_log_filter do
    @desc "Match the url"
    field :url, :string
    @desc "Match the status code"
    field :status_code, :integer
  end

  object :webhook_log_queries do
    @desc "Get a list of all webhook_logs filtered by various criteria"
    field :webhook_logs, list_of(:webhook_log) do
      arg(:filter, :webhook_log_filter)
      arg(:opts, :opts)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WebhookLogs.webhook_logs/3)
    end

    @desc "Get a count of all webhook_logs filtered by various criteria"
    field :count_webhook_logs, :integer do
      arg(:filter, :webhook_log_filter)
      middleware(Authorize, :staff)
      resolve(&Resolvers.WebhookLogs.count_webhook_logs/3)
    end
  end
end
