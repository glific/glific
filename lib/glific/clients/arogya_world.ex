defmodule Glific.Clients.ArogyaWorld do
  alias Glific.{Caches, Clients.OrganizationData, Repo, Sheets.ApiClient}

  @start_date "2022-01-24"

  defp start_date() do
    @start_date
    |> Timex.parse!("{YYYY}-{0M}-{D}")
    |> Timex.to_date()
  end

  def get_week_number,
    do: Timex.diff(Timex.today(), start_date(), :weeks)

  def current_week_and_day() do
    day_name =
      start_date()
      |> Timex.weekday()
      |> Timex.day_name()
      |> Glific.string_clean()
      |> Glific.safe_string_to_atom()

    %{
      week_number: get_week_number(),
      week_day: Timex.weekday(Timex.today(), day_name)
    }
  end

  @spec get_message_teamplate(non_neg_integer, any) :: any
  defp get_message_teamplate(organization_id, message_id) do
    case Caches.fetch(organization_id, "message_hsm_map", &load_message_hsm_map/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve data for key #{"message_hsm_map"} error #{inspect(error)}"
        )

      {_, message_hsm_map} ->
        message_hsm_map[message_id]
    end
  end

  defp load_message_hsm_map(cache_key) do
    {organization_id, key} = cache_key

    {:ok, organization_data} =
      Repo.fetch(OrganizationData, %{organization_id: organization_id, key: key})

    {:commit, organization_data.json}
  end

  defp get_question_teamplate(organization_id, question_id) do
    case Caches.fetch(organization_id, "question_hsm_map", &load_question_hsm_map/1) do
      {:error, error} ->
        raise(ArgumentError,
          message: "Failed to retrieve data for key #{"question_hsm_map"} error #{inspect(error)}"
        )

      {_, question_hsm_map} ->
        question_hsm_map[question_id]
    end
  end

  defp load_question_hsm_map(cache_key) do
    {organization_id, key} = cache_key

    {:ok, organization_data} =
      Repo.fetch(OrganizationData, %{organization_id: organization_id, key: key})

    {:commit, organization_data.json}
  end

  def webhook("static_morning", attrs) do
    ## get current week
    ## get current day
    ## get the message id which we need to send to users
    ## return the template id.
  end

  def webhook("static_noon", attrs) do
    ## get current week
    ## get current day
    ## get the message id which we need to send to users
    ## return the template id.
  end

  def webhook("static_evening", attrs) do
    ## get current week
    ## get current day
    ## get the message id which we need to send to users
    ## return the template id.
  end

  @doc """
  static message id and uuid mapping with weeks and days
  """
  @spec static_week_message_mapping(String.t()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def static_week_message_mapping(file_url) do
    add_data_from_csv(
      "static_week_message_mapping",
      file_url,
      fn acc, data ->
        %{static_week_data: acc.static_week_data ++ [data]}
      end,
      %{static_week_data: []}
    )
  end

  @doc """
  add data that needs to be sent to the database
  """
  @spec add_data_from_csv(String.t(), String.t(), any(), map()) ::
          {:ok, any()} | {:error, Ecto.Changeset.t()}
  def add_data_from_csv(key, file_url, cleanup_func, default_value \\ %{}) do
    # how to validate if the data is in correct format
    data =
      ApiClient.get_csv_content(url: file_url)
      |> Enum.reduce(default_value, fn {_, data}, acc ->
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
    add_data_from_csv("message_hsm_map", file_url, fn acc, data ->
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
    add_data_from_csv("question_hsm_map", file_url, fn acc, data ->
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
  Insert or update data if key present for OrganizationData table.
  """
  @spec maybe_insert_data(String.t(), map()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def maybe_insert_data(key, data) do
    # check if the week key is already present in the database
    case Repo.get_by(OrganizationData, %{key: key}) do
      nil ->
        attrs =
          %{}
          |> Map.put(:key, key)
          |> Map.put(:json, data)
          |> Map.put(:organization_id, 1)

        %OrganizationData{}
        |> OrganizationData.changeset(attrs)
        |> Repo.insert()

      organization_data ->
        organization_data
        |> OrganizationData.changeset(%{json: data})
        |> Repo.update()
    end
  end
end
