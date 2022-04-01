defmodule Glific.Clients.NayiDisha do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  alias Glific.{
    Clients.NayiDisha.Data,
    Contacts,
    Repo
  }

  @day_wise_eng_posters %{
    11 => "https://storage.googleapis.com/ndrc_support_bucket/UDID1.png",
    12 => "https://storage.googleapis.com/ndrc_support_bucket/UDID2.png",
    13 => "https://storage.googleapis.com/ndrc_support_bucket/SelfCarePoster3.png",
    18 =>
      "https://storage.googleapis.com/ndrc_support_bucket/LegalGuardianshipProcedurePoster4.png",
    24 =>
      "https://storage.googleapis.com/ndrc_support_bucket/Financial%20Planning-%20Understanding%20Documents%20Poster7.png",
    25 =>
      "https://storage.googleapis.com/ndrc_support_bucket/Distribution%20of%20affairs-%20options%20poster8.png",
    30 => "https://storage.googleapis.com/ndrc_support_bucket/SelfCarePoster10.png"
  }
  @day_wise_hin_posters %{
    11 => "https://storage.googleapis.com/ndrc_support_bucket/UDIDhin1.png",
    12 => "https://storage.googleapis.com/ndrc_support_bucket/UDIDhin2.png",
    13 => "https://storage.googleapis.com/ndrc_support_bucket/SelfCarePosterhin%201.png",
    18 =>
      "https://storage.googleapis.com/ndrc_support_bucket/LegalGuardianshipProcedureDay18.png",
    24 =>
      "https://storage.googleapis.com/ndrc_support_bucket/Financial%20Planning_Understanding_DocumentsHindiDay24.png",
    25 =>
      "https://storage.googleapis.com/ndrc_support_bucket/Distribution_of_affairs_optionsHindiDay25.png",
    30 => "https://storage.googleapis.com/ndrc_support_bucket/SelfCarePosterhin3.png"
  }
  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    contact_id = get_in(fields, ["contact", "id"])
    contact_language = get_language(contact_id)
    training_day = get_training_day(fields)

    %{
      contact_language: contact_language.locale,
      training_day: training_day,
      is_cycle_ended: training_day not in Map.keys(Data.load()),
      is_valid: Map.has_key?(Data.load(), training_day),
      attachment: get_attachment(contact_language.locale, training_day)
    }
  end

  def webhook(_, _fields), do: %{}

  defp get_attachment(locale, training_day) when training_day in [11, 12, 13, 18, 24, 25, 30],
    do: do_get_attachment(locale, training_day)

  defp get_attachment(_locale, _training_day), do: "non_poster_day"

  defp do_get_attachment("en", training_day),
    do: Map.get(@day_wise_eng_posters, training_day, "non_poster_day")

  defp do_get_attachment("hi", training_day),
    do: Map.get(@day_wise_hin_posters, training_day, "non_poster_day")

  @doc """
    get template for IEX
  """
  @spec template(integer(), String.t()) :: binary
  def template(training_day, language) do
    %{
      uuid: get_in(Data.load(), [training_day, :translations, language, :hsm_uuid]),
      name: "Day #{training_day}",
      variables: get_in(Data.load(), [training_day, :translations, language, :variables]),
      expression: nil
    }
    |> Jason.encode!()
  end

  defp get_language(contact_id) do
    contact =
      contact_id
      |> Contacts.get_contact!()
      |> Repo.preload([:language])

    contact.language
  end

  defp get_training_day(fields) do
    get_in(fields, ["contact", "fields", "training_day", "value"])
    |> Glific.parse_maybe_integer()
    |> case do
      {:ok, training_day} when training_day in [0, nil] ->
        1

      {:ok, training_day} ->
        training_day

      _ ->
        1
    end
  end
end
