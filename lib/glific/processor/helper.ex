defmodule Glific.Processor.Helper do
  @moduledoc """
  Helper functions for all processing modules. Might promote this up at a
  later stage
  """

  alias Glific.{
    Messages.Message,
    Repo,
    Tags,
    Templates.SessionTemplate
  }

  @doc """
  Given a shortcode and an optional language_id, get the session template matching
  both, and if not found, just for the shortcode
  """
  @spec get_session_message_template(String.t(), non_neg_integer, integer | nil) ::
          SessionTemplate.t()
  def get_session_message_template(shortcode, organization_id, language_id \\ nil)

  def get_session_message_template(shortcode, organization_id, nil) do
    {:ok, session_template} =
      Repo.fetch_by(
        SessionTemplate,
        %{shortcode: shortcode, organization_id: organization_id}
      )

    session_template
  end

  def get_session_message_template(shortcode, organization_id, language_id) do
    case Repo.fetch_by(SessionTemplate, %{
           shortcode: shortcode,
           organization_id: organization_id,
           language_id: language_id
         }) do
      {:ok, session_template} -> session_template
      _ -> get_session_message_template(shortcode, organization_id, nil)
    end
  end

  @doc """
  Helper function to add tag
  """
  @spec add_tag(Message.t(), integer, String.t() | nil) :: Message.t()
  def add_tag(message, tag_id, value \\ nil) do
    {:ok, _} =
      Tags.create_message_tag(%{
        message_id: message.id,
        tag_id: tag_id,
        value: value
      })

    message
  end

  @doc """
  Helper function to add tag
  """
  @spec add_dialogflow_tag(Message.t(), map()) :: any()
  def add_dialogflow_tag(_message, %{"intent" => %{"isFallback" => true}}), do: nil

  def add_dialogflow_tag(message, %{"intent" => intent} = response) do
    tag_label =
      intent["displayName"]
      |> String.split(".")
      |> Enum.at(1)

    with {:ok, tag} <-
           Repo.fetch_by(
             Tags.Tag,
             %{label: tag_label, organization_id: message.organization_id}
           ),
         do: add_tag(message, tag.id)

    process_dialogflow_response(response["fulfillmentText"], message)
  end

  # Send the response (reacived from the dialogflow API) to the contact
  @spec process_dialogflow_response(String.t(), map()) :: any()
  defp process_dialogflow_response(nil, _), do: nil
  defp process_dialogflow_response("", _), do: nil

  defp process_dialogflow_response(response_message, message),
    do:
      Glific.Messages.create_and_send_message(%{
        body: response_message,
        receiver_id: message.sender_id,
        organization_id: message.organization_id
      })
end
