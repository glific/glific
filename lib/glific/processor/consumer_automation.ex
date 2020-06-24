defmodule Glific.Processor.ConsumerAutomation do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Messages,
    Messages.Message,
    Repo,
    Settings,
    Tags.MessageTag,
    Tags.Tag,
    Templates.SessionTemplate
  }

  @min_demand 0
  @max_demand 1

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    producer = Keyword.get(opts, :producer, Glific.Processor.ConsumerTagger)
    GenStage.start_link(__MODULE__, [producer: producer], name: name)
  end

  @doc false
  def init(opts) do
    state = %{
      producer: opts[:producer]
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn %{type: type} -> type == :text end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc false
  def handle_events(messages, _from, state) do
    _ =
      messages
      |> Enum.filter(fn m -> Ecto.assoc_loaded?(m.tags) end)
      |> Enum.map(fn m ->
        Enum.map(m.tags, fn t -> process_tag(m, t) end)
      end)

    {:noreply, [], state}
  end

  defp get_session_message_template(shortcode, language_id) do
    result =
      Repo.fetch_by(SessionTemplate, %{
        shortcode: shortcode,
        language_id: language_id
      })

    case result do
      {:ok, session_template} -> session_template
      _ -> get_session_message_template(shortcode)
    end
  end

  defp get_session_message_template(shortcode) do
    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        shortcode: shortcode
      })

    session_template
  end

  defp send_session_message_template(message, shortcode) do
    message = Repo.preload(message, :sender)
    language_id = message.sender.language_id

    session_template = get_session_message_template(shortcode, language_id)

    {:ok, message} =
      Messages.create_and_send_session_template(session_template, message.sender_id)

    message
  end

  @spec process_tag(Message.t(), Tag.t()) :: Message.t()
  defp process_tag(message, %Tag{label: label}) when label == "New Contact" do
    send_session_message_template(message, "new contact")
  end

  defp process_tag(message, %Tag{label: label}) when label == "Optout" do
    # lets send the message first, so it goes out
    send_session_message_template(message, "optout")

    # We need to update the contact with optout_time and status
    query = from(c in Contact, where: c.id == ^message.sender_id)

    Repo.update_all(query,
      set: [status: "invalid", optout_time: DateTime.utc_now(), updated_at: DateTime.utc_now()]
    )
  end

  defp process_tag(message, %Tag{label: label}) when label == "Help" do
    send_session_message_template(message, "help")
  end

  defp process_tag(message, %Tag{label: label} = tag) when label == "Language" do
    {:ok, message_tag} = Repo.fetch_by(MessageTag, %{message_id: message.id, tag_id: tag.id})
    [language | _] = Settings.list_languages(%{label: message_tag.value})

    # We need to update sender id and set their language to this language
    query = from(c in Contact, where: c.id == ^message.sender_id)

    Repo.update_all(query,
      set: [language_id: language.id, updated_at: DateTime.utc_now()]
    )

    session_template = get_session_message_template("language", language.id)

    Map.put(
      session_template,
      :body,
      EEx.eval_string(session_template.body, language: language.label_locale)
    )

    {:ok, message} =
      Messages.create_and_send_session_template(session_template, message.sender_id)

    message
  end

  defp process_tag(message, _tag), do: message
end
