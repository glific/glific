defmodule Glific.EventsConditionsActions.Event do
  @moduledoc """
  First stab at representing our rule engine in a programmatic format. We are using the
  [ECA model](https://en.wikipedia.org/wiki/Event_condition_action) as defined here.

  Did not find any implementation of this in hexdocs, hence rolling our own to get a sense of
  the complexity
  """

  alias Glific.{
    Enums.MessageTypes,
  }

  @conditions %{
    message: %{
      type: :message,
      filters: %{
        type: MessageTypes,
        tags: [], # We will load this dynamically from the DB at init time
        parent_type: MessageTypes,
        parent_tags: [], # Same deal as tags
        ancestors_type: MessageTypes,
        ancestors_tags: [], # Same deal as tags
        body: [:has_any, :has_all, :has_phrase, :has_only_phrase, :is_number]
      }
    },
    message_tag: %{
      type: :message_tag,
      filters: %{
        tags: [], # We will load this dynamically from the DB at init time
        value: [:has_any, :has_all],
      }
    }
  }

  @events %{
    message_received: @conditions[:message],
    message_sent: @conditions[:message],
    # untagged is the same as tag, we create the message
    # without the deleted tag
    message_tagged: @conditions[:message_tag],
  }

  @actions %{
    add_tag_to_message: %{
      params: [:message, :tag, :string],
      return: [:message],
    },

    remove_tag_from_message: %{
      params: [:message, :tag],
      return: [:message],
    },

    send_session_templates: %{
      params: [:message, :session_template, :when],
      return: [:message]
    },
  }

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
