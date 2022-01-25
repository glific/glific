defmodule Glific.Clients.ArogyaWorld do
  alias Glific.Caches
  alias Glific.Clients.ClientData
  alias Glific.Repo

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
    {:ok, client_data} = Repo.fetch(ClientData, %{organization_id: organization_id, key: key})
    {:commit, client_data.json}
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
    {:ok, client_data} = Repo.fetch(ClientData, %{organization_id: organization_id, key: key})
    {:commit, client_data.json}
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
end
