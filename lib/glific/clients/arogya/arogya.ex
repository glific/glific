defmodule Glific.Clients.Arogya do
  @moduledoc """
  Fetching data from CSV and using it to send messages for Arogya usecase.
  """

  alias Glific.{
    Partners.OrganizationsData,
    Repo
  }

  @doc """
  Fetches and cleans the data from the CSV file given a public URL.
  """
  @spec fetch_data_from_csv(String.t()) :: list()
  def fetch_data_from_csv(url) do
    # need to check if the link is not valid
    {:ok, response} = Tesla.get(url)
    {:ok, stream} = StringIO.open(response.body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(headers: true, strip_fields: true)
    |> Enum.reduce(%{}, fn {_, data}, acc ->
      acc |> Map.put_new(data["ID"], cleanup_csv_data(data))
    end)

    # how to validate if the data is in correct format
  end

  @doc """
  Clean the data from the CSV file.
  """
  @spec cleanup_csv_data(map()) :: map()
  def cleanup_csv_data(data) do
    %{
      message_one_id: data["M1_ID"],
      question_one_id: data["Q1_ID"],
      message_two_id: data["M2_ID"],
      question_two_id: data["Q2_ID"]
    }
  end

  @doc """
  add weekly data that needs to be sent to the database
  """
  @spec add_weekly_data(String.t(), String.t()) :: map()
  def add_weekly_data(week, file_url) do
    data = fetch_data_from_csv(file_url)

    # check if the week key is already present in the database
    case Repo.get_by(OrganizationsData, %{key: week}) do
      nil ->
        attr =
          %{}
          |> Map.put(:key, week)
          |> Map.put(:value, data)
          |> Map.put(:organization_id, 1)

        %OrganizationsData{}
        |> OrganizationsData.changeset(attr)
        |> Repo.insert()

      organizations_data ->
        organizations_data
        |> OrganizationsData.changeset(%{value: data})
        |> Repo.update()
    end
  end
end
