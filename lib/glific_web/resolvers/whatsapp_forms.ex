defmodule GlificWeb.Resolvers.WhatsappForms do
  @moduledoc """
  Resolver for Meta API related operations.
  """

  alias Glific.ThirdParty.Meta.ApiClientMeta

  def publish_wa_form(_parent, %{flow_id: flow_id}, _resolution) do
    case ApiClientMeta.publish_wa_form(flow_id) do
      {:ok, response} ->
        {:ok, %{success: true, message: "Flow published successfully", data: response}}

      {:error, error_message} ->
        {:ok, %{success: false, message: error_message, data: nil}}
    end
  end
end
