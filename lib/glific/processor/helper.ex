defmodule Glific.Processor.Helper do
  @moduledoc """
  Helper functions for all processing modules. Might promote this up at a
  later stage
  """

  alias Glific.{
    Messages.Message,
    Repo,
    Tags
  }

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
    IO.inspect("Cleanupsss 1")
    IO.inspect(message)

    tag_label =
      case intent["displayName"]
           |> String.split(".")
           |> Enum.at(1) do
        nil -> intent["displayName"]
        tag_label -> tag_label
      end

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

  defp process_dialogflow_response(response_message, message) do
    IO.inspect("Cleanupsss")
    IO.inspect(message)
      Glific.Messages.create_and_send_message(%{
        body: response_message,
        receiver_id: message.sender_id,
        organization_id: message.organization_id
      })


  end
end
