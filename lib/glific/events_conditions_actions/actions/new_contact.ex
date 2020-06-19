defmodule Glific.EventsConditionsActions.Action.NewContact do
  @moduledoc """
  Lets treat the new contacts as special and do it only for the first time this contact has been
  tagged as a new contact
  """

  alias Glific.{
    Messages,
    Messages.Message,
    Repo,
    Taggers.Status,
    Templates.SessionTemplate
  }

  @doc false
  @spec init(:ok) :: map()
  def init(:ok) do
    %{
      status_map: Status.get_status_map()
    }
  end

  @doc """
  Interface to check if the event matches this action
  """
  @spec condition(%{atom() => any}, map()) :: boolean
  def condition(%{message: message}, state) do
    # we have a message preloaded with all its tags, lets check
    # if there is a new contact tag
    Messages.tag_in_message?(message, state.status_map["New Contact"])
  end

  @doc false
  @spec perform(%{message: Message.t()}, map()) :: {map(), map()}
  def perform(%{message: message}, state) do
    # lets send the welcome message to the new contact
    {:ok, session_template} = Repo.fetch_by(SessionTemplate, %{shortcode: "new contact"})

    {:ok, sent_message} =
      Messages.create_and_send_session_template(session_template, message.sender_id)

    {%{message: message, sent_message: sent_message}, state}
  end
end
