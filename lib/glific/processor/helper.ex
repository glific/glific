defmodule Glific.Processor.Helper do
  @moduledoc """
  Helper functions for all processing modules. Might promote this up at a
  later stage
  """

  alias Glific.{
    Messages.Message,
    Repo,
    Tags,
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
end
