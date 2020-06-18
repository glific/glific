defmodule Glific.EventsConditionsActions.Action do
  @moduledoc """
  The API container that exposes all actions. These functions do minimal work, but harness the power
  of the respective context APIs
  """

  alias Glific.{
    Communications,
    Messages,
    Messages.Message,
    Repo,
    Tags,
    Tags.Tag,
    Templates.SessionTemplate
  }

  @doc false
  @spec add_tag_to_message(Message.t(), Tag.t(), String.t() | nil) :: Message.t()
  def add_tag_to_message(message, tag, value \\ nil) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: tag.id,
      value: value
    })
    # now publish the message tag event
    |> Communications.publish_data(:created_message_tag)

    Repo.preload(message, [:tags])
  end

  @doc false
  @spec remove_tag_from_message(Message.t(), Tag.t()) :: Message.t()
  def remove_tag_from_message(message, tag) do
    {:ok, message_tag} =
      Repo.fetch_by(MessageTag, %{
        message_id: message.id,
        tag_id: tag.id
      })

    Tags.delete_message_tag(message_tag)
    # now publish the message tag event
    |> Communications.publish_data(:deleted_message_tag)

    Repo.preload(message, [:tags])
  end

  @doc false
  @spec send_session_templates(SessionTemplate.t(), Message.t()) :: Message.t()
  def send_session_templates(session_template, message) do
    {:ok, message} =
      Messages.create_and_send_session_template(session_template.id, message.receiver_id)

    message
  end
end
