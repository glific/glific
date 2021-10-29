defmodule Glific.Clients.NayiDisha do
  @moduledoc """
  Custom webhook implementation specific to NayiDisha usecase
  """

  alias Glific.Contacts
  alias Glific.Repo

  @parent_hsm_uuid "2f9c4fb1-2bcb-4f8d-b9a0-80e366e1e43d"

  @hsm %{
    1 => %{
      hsm_uuid: @parent_hsm_uuid,
      variables: [
        "Covid 19 cases are still on the rise. Therefore, we request you to continue taking preventive measures at all times. In this question series Neuro-Developmental Pediatrician Dr. Ajay Sharma talks about some common concerns about Covid-19 and and vaccinations to manage the illness in children who need special care.

      Dr.Ajay Sharma is a consultant Neurodevelopmental Paediatrician and the ex-Clinical Director at Evelina London, Guy’s and St Thomas’ Hospital, UK.
      Click on this link to listen to the question series👉 https://www.nayi-disha.org/article/covid-19-care-illness-and-its-vaccine-special-children-english
      "
      ],
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
