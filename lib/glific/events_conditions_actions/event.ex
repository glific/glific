defmodule Glific.EventsConditionsActions.Event do
  @moduledoc """
  First stab at representing our rule engine in a programmatic format. We are using the
  [ECA model](https://en.wikipedia.org/wiki/Event_condition_action) as defined here.

  Did not find any implementation of this in hexdocs, hence rolling our own to get a sense of
  the complexity
  """

  alias Glific.{
    Enums.MessageTypes,
    EventsConditionsActions.Action
  }

  @conditions %{
    message: %{
      type: :message,
      filters: %{
        type: MessageTypes,
        # We will load this dynamically from the DB at init time
        tags: [],
        parent_type: MessageTypes,
        # Same deal as tags
        parent_tags: [],
        ancestors_type: MessageTypes,
        # Same deal as tags
        ancestors_tags: [],
        body: [:has_any, :has_all, :has_phrase, :has_only_phrase, :is_number]
      }
    },
    message_tag: %{
      type: :message_tag,
      filters: %{
        # We will load this dynamically from the DB at init time
        tags: [],
        value: [:has_any, :has_all]
      }
    }
  }

  @events %{
    message_received: @conditions[:message],
    message_sent: @conditions[:message],
    # untagged is the same as tag, we create the message
    # without the deleted tag
    message_tagged: @conditions[:message_tag]
  }

  @actions %{
    add_tag_to_message: Action,
    remove_tag_from_message: Action,
    send_session_template: Action
  }

  @doc false
  @spec init() :: %{atom() => map()}
  def init do
    %{
      events: @events,
      conditions: load_from_db(@conditions),
      actions: @actions
    }
  end

  defp load_from_db(conditions) do
    conditions
  end
end
