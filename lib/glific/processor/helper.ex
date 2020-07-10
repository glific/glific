defmodule Glific.Processor.Helper do
  @moduledoc """
  Helper functions for all processing modules. Might promote this up at a
  later stage
  """

  alias Glific.{
    Messages,
    Messages.Message,
    Repo,
    Tags,
    Tags.Tag,
    Templates.SessionTemplate
  }

  @doc """
  Given a shortcode and an optional language_id, get the session template matching
  both, and if not found, just for the shortcode
  """
  @spec get_session_message_template(String.t(), integer | nil) :: SessionTemplate.t()
  def get_session_message_template(shortcode, language_id \\ nil)

  def get_session_message_template(shortcode, nil) do
    {:ok, session_template} = Repo.fetch_by(SessionTemplate, %{shortcode: shortcode})

    session_template
  end

  def get_session_message_template(shortcode, language_id) do
    case Repo.fetch_by(SessionTemplate, %{
           shortcode: shortcode,
           language_id: language_id
         }) do
      {:ok, session_template} -> session_template
      _ -> get_session_message_template(shortcode, nil)
    end
  end

  @doc """
  Send a reply to the current sender of the incoming message in the preferred
  language of the sender
  """
  @spec send_session_message_template(Message.t(), String.t()) :: Message.t()
  def send_session_message_template(message, shortcode) do
    message = Repo.preload(message, :sender)
    language_id = message.sender.language_id

    session_template = get_session_message_template(shortcode, language_id)

    {:ok, message} =
      Messages.create_and_send_session_template(session_template, message.sender_id)

    message
  end

  @doc """
  Send a reply to the current sender of the incoming message in the preferred
  language of the sender and associate a tag with it
  """
  @spec send_session_message_template_with_tag(Message.t(), Tag.t(), String.t(), String.t()) ::
          Message.t()
  def send_session_message_template_with_tag(message, tag, value, shortcode) do
    sent_message = send_session_message_template(message, shortcode)

    # now tag this message
    add_tag(sent_message, tag.id, value)
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

  @min_demand 0
  @max_demand 1

  @doc """
  Common function for downstream consumers since they follow the same pattern
  """
  @spec start_link([], atom()) :: GenServer.on_start()
  def start_link(opts, module) do
    name = Keyword.get(opts, :name, module)
    producer = Keyword.get(opts, :producer, Glific.Processor.ConsumerTagger)
    GenStage.start_link(module, [producer: producer], name: name)
  end

  @doc false
  @spec init([], String.t() | nil) :: tuple()
  def init(opts, label \\ nil) do
    state = %{
      producer: opts[:producer]
    }

    {:consumer, state,
     subscribe_to: [
       {state.producer,
        selector: fn [_, %{label: l}] -> l == label end,
        min_demand: @min_demand,
        max_demand: @max_demand}
     ]}
  end

  @doc false
  @spec handle_events([], any, map(), (any, any -> any)) :: tuple()
  def handle_events(messages_tags, _from, state, processFn) do
    _ = Enum.map(messages_tags, fn [m, t] -> processFn.(m, t) end)
    {:noreply, [], state}
  end
end
