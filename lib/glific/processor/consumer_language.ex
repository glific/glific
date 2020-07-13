defmodule Glific.Processor.ConsumerLanguage do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  # import Ecto.Query

  alias Glific.{
    Flows.Flow,
    Messages.Message,
    Processor.Helper,
    Repo,
    Tags.Tag
  }

  # alias Glific.{
  #   Contacts.Contact,
  #   Messages,
  #   Messages.Message,
  #   Repo,
  #   Settings,
  #   Tags.MessageTag,
  #   Tags.Tag
  # }

  @doc false
  @spec start_link([]) :: GenServer.on_start()
  def start_link(opts) do
    Helper.start_link(opts, __MODULE__)
  end

  @doc false
  def init(opts) do
    Helper.init(opts, "Language")
  end

  @doc false
  def handle_events(messages_tags, from, state) do
    Helper.handle_events(messages_tags, from, state, &process_tag/2)
  end

  @doc """
  Process the language tag. Send a confirmation to the sender and set the contact fields
  """
  @spec process_tag(Message.t(), Tag.t()) :: any
  def process_tag(message, _tag) do
    message = Repo.preload(message, :contact)
    Flow.start_flow("language", message.contact)
    # {:ok, message_tag} = Repo.fetch_by(MessageTag, %{message_id: message.id, tag_id: tag.id})
    # [language | _] = Settings.list_languages(%{label: message_tag.value})

    # # We need to update sender id and set their language to this language
    # query = from(c in Contact, where: c.id == ^message.sender_id)

    # Repo.update_all(query,
    #   set: [language_id: language.id, updated_at: DateTime.utc_now()]
    # )

    # session_template = Helper.get_session_message_template("language", language.id)

    # {:ok, message} =
    #   "language"
    #   |> Helper.get_session_message_template(language.id)
    #   |> Map.put(
    #     :body,
    #     EEx.eval_string(session_template.body, language: language.label_locale)
    #   )
    #   |> Messages.create_and_send_session_template(message.sender_id)

    message
  end
end
