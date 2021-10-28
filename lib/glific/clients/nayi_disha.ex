defmodule Glific.Clients.NayiDisha do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  alias Glific.Contacts
  alias Glific.Repo

  @hsm %{
    1 => %{
      hsm_uuid: "5be94a85-8d90-4257-9d69-1c3d9c5017cc",
      variables: ["@contact.phone"],
      translations: %{
        "hi" => %{
          variables: []
        }
      }
    },
    2 => %{
      hsm_uuid: "12ffe891-debd-4ed8-8595-c0099e277ac3",
      variables: ["@contact.name"],
      translations: %{
        "hi" => %{
          variables: []
        }
      }
    }
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
      is_valid: Map.has_key?(@hsm, training_day)
    }
  end

  def webhook(_, _fields),
    do: %{}

  def template(training_day) do
    %{
      uuid: get_in(@hsm, [training_day, :hsm_uuid]),
      name: "Day #{training_day}",
      variables: get_in(@hsm, [training_day, :variables]),
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
        IO.inspect("got a training day")
        IO.inspect(training_day)
        training_day

      _ ->
        1
    end
  end
end
