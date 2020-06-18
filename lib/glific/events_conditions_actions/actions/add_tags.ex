defmodule Glific.EventsConditionsActions.Action.AddTags do
  @moduledoc """
  The API container that exposes all actions. These functions do minimal work, but harness the power
  of the respective context APIs
  """

  alias Glific.{
    Communications,
    Messages.Message,
    Repo,
    Taggers,
    Taggers.Keyword,
    Taggers.Numeric,
    Taggers.Status,
    Tags,
    Tags.Tag
  }

  @doc false
  def init(:ok) do
    state = %{
      producer: Glific.Processor.Producer,
      keyword_map: Keyword.get_keyword_map(),
      status_map: Status.get_status_map(),
      numeric_map: Numeric.get_numeric_map(),
      numeric_tag_id: 0
    }

    case Repo.fetch_by(Tag, %{label: "Numeric"}) do
      {:ok, tag} -> Map.put(state, :numeric_tag_id, tag.id)
      _ -> state
    end
  end

  @doc false
  @spec perform(%{atom() => any}, map()) :: {%{atom() => any}, map()}
  def perform(%{message: message}, state) do
    body = Taggers.string_clean(message.body)

    message =
      message
      |> add_unread_tag(state)
      |> new_contact_tagger(state)
      |> numeric_tagger(body, state)
      |> keyword_tagger(body, state)
      |> Repo.preload(message, [:tags])
      |> Communications.publish_data(:created_message_tag)

    {%{message: message}, state}
  end

  @spec numeric_tagger(atom() | Message.t(), String.t(), map()) :: Message.t()
  defp numeric_tagger(message, body, state) do
    case Numeric.tag_body(body, state.numeric_map) do
      {:ok, value} -> add_numeric_tag(message, value, state)
      _ -> message
    end
  end

  @spec keyword_tagger(atom() | Message.t(), String.t(), map()) :: Message.t()
  defp keyword_tagger(message, body, state) do
    case Keyword.tag_body(body, state.keyword_map) do
      {:ok, value} -> add_keyword_tag(message, value, state)
      _ -> message
    end
  end

  @spec new_contact_tagger(Message.t(), map()) :: Message.t()
  defp new_contact_tagger(message, state) do
    if Status.is_new_contact(message.sender_id) do
      add_new_user_tag(message, state)
    end

    message
  end

  @spec add_unread_tag(Message.t(), map()) :: Message.t()
  defp add_unread_tag(message, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.status_map["Unread"]
    })

    message
  end

  @spec add_new_user_tag(Message.t(), map()) :: Message.t()
  defp add_new_user_tag(message, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.status_map["New User"]
    })

    message
  end

  @spec add_numeric_tag(Message.t(), String.t(), atom() | map()) :: Message.t()
  defp add_numeric_tag(message, value, state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: state.numeric_tag_id,
      value: value
    })

    message
  end

  @spec add_keyword_tag(Message.t(), String.t(), atom() | map()) :: Message.t()
  defp add_keyword_tag(message, value, _state) do
    Tags.create_message_tag(%{
      message_id: message.id,
      tag_id: String.to_integer(value)
    })

    message
  end
end
