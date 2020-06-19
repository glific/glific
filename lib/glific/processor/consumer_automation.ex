defmodule Glific.Processor.ConsumerAutomation do
  @moduledoc """
  Process all messages of type consumer and run them thru a few automations. Our initial
  automation is response to a new contact tag with a welcome message
  """

  use GenStage

  import Ecto.Query

  alias Glific.{
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
  @spec start_link(any) :: GenServer.on_start()
  def start_link(_), do: GenStage.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc false
  def init(:ok) do
    state = %{
      producer: Glific.Processor.ConsumerTagger
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
  def handle_info(_, state), do: {:noreply, [], state}

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

  @spec process_tag(Message.t(), Tag.t()) :: Message.t()
  defp process_tag(message, %Tag{label: label}) when label == "New Contact" do
    message =
      message
      |> join(:left, [msg], _ in assoc(msg, :sender))
      |> join(:left, [msg, sender], _ in assoc(sender, :language))
      |> preload([_, sender, language], sender: {sender, language: language})
      |> Repo.one()

    with {:ok, session_template} <-
           Repo.fetch_by(SessionTemplate, %{
             shortcode: "new contact",
             language_id: message.sender.language_id
           }),
         {:ok, message} <-
           Messages.create_and_send_session_template(session_template, message.sender_id),
         do: message
  end

  defp process_tag(message, %Tag{label: label} = tag) when label == "Language" do
    {:ok, message_tag} = Repo.fetch_by(MessageTag, %{message_id: message.id, tag_id: tag.id})
    [language | _] = Settings.list_languages(%{label: message_tag.value})

    # We need to update sender id and set their language to this language

    with {:ok, session_template} <-
           Repo.fetch_by(SessionTemplate, %{shortcode: "language", language_id: language.id}),
         {:ok, message} <-
           Messages.create_and_send_session_template(session_template, message.sender_id),
         do: message
  end

  defp process_tag(message, _tag), do: message
end
