defmodule Glific.Clients.ArogyaWorld do
  @moduledoc """
  Fetching data from CSV and using it to send messages for Arogya usecase.
  """

  alias Glific.{
    Clients.ClientData,
    Repo,
    Sheets.ApiClient
  }

  @start_date "2022-01-24"

  defp start_date() do
    @start_date
    |> Timex.parse!("{YYYY}-{0M}-{D}")
    |> Timex.to_date()
  end

  def get_week do
    Timex.diff(Timex.today(), start_date(), :weeks)
  end

  def current_week_and_day() do
    week_day = Timex.weekday(start_date())
    day_name = Timex.day_name(week_day)
    {get_week(), Timex.weekday(Timex.today()), day_name}
  end

  @doc """
  add data that needs to be sent to the database
  """
  @spec add_data_from_csv(String.t(), String.t(), any()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_data_from_csv(key, file_url, cleanup_func) do
    # how to validate if the data is in correct format
    data =
      ApiClient.get_csv_content(url: file_url)
      |> Enum.reduce(%{}, fn {_, data}, acc ->
        cleanup_func.(acc, data)
      end)

    maybe_insert_data(key, data)
  end

  @doc """
  message mapping to HSM UUID
  """
  @spec message_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def message_hsm_mapping(file_url) do
    add_data_from_csv("message_id_hsm_map", file_url, fn acc, data ->
      acc
      |> Map.put_new(data["MESSAGE_ID"], data["HSM_UUID"])
    end)
  end

  @doc """
  question mapping to HSM UUID
  """
  @spec question_hsm_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def question_hsm_mapping(file_url) do
    add_data_from_csv("question_id_hsm_map", file_url, fn acc, data ->
      acc
      |> Map.put_new(data["QUESTION_ID"], data["HSM_UUID"])
    end)
  end

  @doc """
  Clean week data from the CSV file.
  """
  @spec cleanup_week_data(map(), map()) :: map()
  def cleanup_week_data(acc, data) do
    attr = %{
      message_one_id: data["M1_ID"],
      question_one_id: data["Q1_ID"],
      message_two_id: data["M2_ID"],
      question_two_id: data["Q2_ID"]
    }

    acc
    |> Map.put_new(data["ID"], attr)
  end

  @doc """
  Insert or update data if key present for ClientData table.
  """
  @spec maybe_insert_data(String.t(), map()) ::
          {:ok, ClientData.t()} | {:error, Ecto.Changeset.t()}
  def maybe_insert_data(key, data) do
    # check if the week key is already present in the database
    case Repo.get_by(ClientData, %{key: key}) do
      nil ->
        attrs =
          %{}
          |> Map.put(:key, key)
          |> Map.put(:json, data)
          |> Map.put(:organization_id, 1)

        %ClientData{}
        |> ClientData.changeset(attrs)
        |> Repo.insert()

      client_data ->
        client_data
        |> ClientData.changeset(%{json: data})
        |> Repo.update()
    end
  end
end
