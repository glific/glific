defmodule Glific.Clients.SunoSunao do
  @moduledoc """
  This module will focus on suno sunao usecase
  """

  alias Glific.{ASR.GoogleASR, Contacts.Contact, Repo}

  @doc """
  This is a webhook which will call into google speech to text api
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("speech_to_text", fields) do
    contact_id = Glific.parse_maybe_integer!(fields["contact"]["id"])
    contact = get_contact_language(contact_id)

    Glific.parse_maybe_integer!(fields["organization_id"])
    |> GoogleASR.speech_to_text(fields["results"], contact.language.locale)
  end

  defp get_contact_language(contact_id) do
    case Repo.fetch(Contact, contact_id) do
      {:ok, contact} -> contact |> Repo.preload(:language)
      {:error, error} -> error
    end
  end
end
