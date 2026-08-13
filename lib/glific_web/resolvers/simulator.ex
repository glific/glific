defmodule GlificWeb.Resolvers.Simulator do
  @moduledoc """
  Resolver for the staff-console flow preview simulator's web-channel mutation
  (`plans/web-channel/blocks-contract.md` §13). Sits between the GraphQL schema and
  `Glific.Communications.WebMessage`, authorizing the target contact and then funneling into
  the same inbound path `GlificWeb.WebChannel.RoomChannel.handle_in/3` uses for a real browser
  contact — a staff session holds no contact token to join that channel itself (§13.1).
  """

  alias Glific.{
    Communications.WebMessage,
    Contacts,
    Contacts.Contact,
    Repo
  }

  @doc """
  Drive one simulated inbound web-channel message for a simulator contact.
  """
  @spec simulator_web_message(Absinthe.Resolution.t(), %{input: map()}, %{context: map()}) ::
          {:ok, map()} | {:error, any()}
  def simulator_web_message(_, %{input: params}, %{context: %{current_user: user}}) do
    with {:ok, contact} <- fetch_simulator_contact(params.contact_id, user.organization_id),
         {:ok, {message_params, type}} <- to_web_message_params(contact, params),
         {:ok, message} <- WebMessage.receive_message(message_params, type) do
      {:ok, %{message: message}}
    end
  end

  # This is the whole authorization story: re-scoped to the caller's org (a contact id from
  # another org simply isn't found, same as every other by-id resolver lookup), and rejected
  # unless it is a simulator contact — so a staff user of org A can neither drive a simulator
  # contact of org B, nor drive a real contact of their own org through this path.
  @spec fetch_simulator_contact(String.t() | integer(), non_neg_integer()) ::
          {:ok, Contact.t()} | {:error, String.t() | [String.t()]}
  defp fetch_simulator_contact(contact_id, organization_id) do
    with {:ok, contact} <-
           Repo.fetch_by(Contact, %{id: contact_id, organization_id: organization_id}) do
      if Contacts.simulator_contact?(contact.phone),
        do: {:ok, contact},
        else: {:error, "contact is not a simulator contact"}
    end
  end

  # Mirrors `GlificWeb.WebChannel.RoomChannel.handle_in/3` clause-for-clause: same params shape,
  # same type atom, per message kind. No business logic here — correlation, the atomic
  # single-submit and envelope validation all live below `WebMessage.receive_message/2`.
  @spec to_web_message_params(Contact.t(), map()) ::
          {:ok, {map(), atom()}} | {:error, String.t()}
  defp to_web_message_params(contact, %{type: :text} = params) do
    {:ok,
     {%{
        sender: %{phone: contact.phone},
        organization_id: contact.organization_id,
        body: params[:body]
      }, :text}}
  end

  defp to_web_message_params(contact, %{type: type} = params)
       when type in [:image, :audio, :video, :document] do
    caption = params[:body]

    {:ok,
     {%{
        sender: %{phone: contact.phone},
        organization_id: contact.organization_id,
        url: params[:url],
        source_url: params[:url],
        caption: caption,
        content_type: params[:content_type],
        body: caption || ""
      }, type}}
  end

  defp to_web_message_params(contact, %{type: :location} = params) do
    latitude = params[:latitude]
    longitude = params[:longitude]

    {:ok,
     {%{
        sender: %{phone: contact.phone},
        organization_id: contact.organization_id,
        longitude: longitude,
        latitude: latitude,
        body: "https://www.google.com/maps?q=#{latitude},#{longitude}"
      }, :location}}
  end

  defp to_web_message_params(contact, %{type: :blocks_response} = params) do
    {:ok,
     {%{
        "message_id" => parse_message_id(params[:message_id]),
        "component" => params[:component],
        "values" => params[:values],
        "summary" => params[:summary],
        "context" => params[:context],
        sender: %{phone: contact.phone},
        organization_id: contact.organization_id
      }, :blocks_response}}
  end

  defp to_web_message_params(_contact, %{type: type}),
    do: {:error, "unsupported simulator message type: #{type}"}

  @spec parse_message_id(String.t() | nil) :: non_neg_integer() | nil
  defp parse_message_id(nil), do: nil
  defp parse_message_id(id), do: String.to_integer(id)
end
