defmodule Glific.Processor.Helper do
  @moduledoc """
  Helper functions for all processing modules. Might promote this up at a
  later stage
  """

  alias Glific.{
    Messages,
    Messages.Message,
    Repo,
    Templates.SessionTemplate
  }

  @doc """
  Given a shortcode and an optional language_id, get the session template matching
  both, and if not found, just for the shortcode
  """
  @spec get_session_message_template(String.t(), integer) :: SessionTemplate.t()
  def get_session_message_template(shortcode, language_id) do
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

  @doc """
  Given a shortcode get the session template matching it.
  """
  @spec get_session_message_template(String.t()) :: SessionTemplate.t()
  def get_session_message_template(shortcode) do
    {:ok, session_template} =
      Repo.fetch_by(SessionTemplate, %{
        shortcode: shortcode
      })

    session_template
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
end
