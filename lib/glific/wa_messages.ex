defmodule Glific.WAMessages do
  @moduledoc """
  Whatsapp messages context
  """
  alias Glific.Contacts
  alias Glific.Flows.MessageVarParser
  alias Glific.Messages
  alias Glific.Repo
  alias Glific.WAGroup.WAMessage

  @doc """
  Creates a message.
  ## Examples
      iex> create_message(%{field: value})
      {:ok, %WAMessage{}}
      iex> create_message(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_message(map()) :: {:ok, WAMessage.t()} | {:error, Ecto.Changeset.t()}
  def create_message(attrs) do
    attrs =
      %{flow: :inbound, status: :enqueued}
      |> Map.merge(attrs)
      |> parse_message_vars()
      |> put_clean_body()

    %WAMessage{}
    |> WAMessage.changeset(attrs)
    |> Repo.insert(
      returning: [:message_number, :uuid, :context_message_id],
      timeout: 45_000
    )
  end

  @doc false
  @spec update_message(WAMessage.t(), map()) ::
          {:ok, WAMessage.t()} | {:error, Ecto.Changeset.t()}
  def update_message(%WAMessage{} = message, attrs) do
    message
    |> WAMessage.changeset(attrs)
    |> Repo.update()
  end

  @spec parse_message_vars(map()) :: map()
  defp parse_message_vars(attrs) do
    message_vars =
      if is_integer(attrs[:contact_id]) or is_binary(attrs[:contact_id]),
        do: %{"contact" => Contacts.get_contact_field_map(attrs.contact_id)},
        else: %{}

    parse_text_message_fields(attrs, message_vars)
    |> parse_media_message_fields(message_vars)
  end

  @spec parse_text_message_fields(map(), map()) :: map()
  defp parse_text_message_fields(attrs, message_vars) do
    if is_binary(attrs[:body]) do
      {:ok, msg_uuid} = Ecto.UUID.cast(:crypto.hash(:md5, attrs.body))

      attrs
      |> Map.merge(%{
        uuid: attrs[:uuid] || msg_uuid,
        body: MessageVarParser.parse(attrs.body, message_vars)
      })
    else
      attrs
    end
  end

  @spec parse_media_message_fields(map(), map()) :: map()
  defp parse_media_message_fields(attrs, message_vars) do
    ## if message media is present change the variables in caption
    if is_integer(attrs[:media_id]) or is_binary(attrs[:media_id]) do
      message_media = Messages.get_message_media!(attrs.media_id)

      message_media
      |> Messages.update_message_media(%{
        caption: MessageVarParser.parse(message_media.caption, message_vars)
      })
    end

    attrs
  end

  @spec put_clean_body(map()) :: map()
  # sometimes we get no body, so we need to ensure we set to null for text type
  # Issue #2798
  defp put_clean_body(%{body: nil, type: :text} = attrs),
    do:
      attrs
      |> Map.put(:body, "")
      |> Map.put(:clean_body, "")

  defp put_clean_body(%{body: body} = attrs),
    do: Map.put(attrs, :clean_body, Glific.string_clean(body))

  defp put_clean_body(attrs), do: attrs
end
