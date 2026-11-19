defmodule Glific.Providers.Gupshup.V3.Handlers.FormResponse do
  @moduledoc """
  Receives a WhatsApp form response (an nfm_reply interactive message) from a
  Gupshup V3 messages change.
  """

  @behaviour Glific.Providers.Gupshup.V3.Handler

  alias Glific.Communications
  alias Glific.Providers.Gupshup
  alias Glific.Providers.Gupshup.Instrumentation

  @impl true
  @spec handle(map(), non_neg_integer()) :: :ok
  def handle(%{"messages" => [message | _], "contacts" => [contact | _]}, organization_id) do
    {message, contact}
    |> Gupshup.Message.receive_whatsapp_form_response()
    |> Map.put(:organization_id, organization_id)
    |> put_in([:sender, :contact_type], "WABA")
    |> Communications.Message.receive_message(:whatsapp_form_response)

    Instrumentation.track_receive("whatsapp_form_response handler", organization_id)
  end

  def handle(_value, _organization_id), do: :ok
end
