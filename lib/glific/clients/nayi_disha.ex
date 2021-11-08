defmodule Glific.Clients.NayiDisha do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  alias Glific.{
    Clients.NayiDisha.Data,
    Contacts,
    Repo
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    contact_id = get_in(fields, ["contact", "id"])
    _contact_language = get_language(contact_id)
    training_day = get_training_day(fields)

    %{
      training_day: training_day,
      is_cycle_ended: training_day not in Map.keys(Data.load()),
      is_valid: Map.has_key?(Data.load(), training_day)
    }
  end

  def webhook(_, _fields),
    do: %{}

  @doc """
    get template for IEX
  """
  @spec template(integer()) :: binary
  def template(training_day) do
    %{
      uuid: get_in(Data.load(), [training_day, :hsm_uuid]),
      name: "Day #{training_day}",
      variables: get_in(Data.load(), [training_day, :variables]),
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
