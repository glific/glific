defmodule Glific.Clients.ReapBenefit do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.Flow,
    Repo
  }

  @frappe_open_civic_api_url "http://frappe.solveninja.org/api/"

  @doc """
  In the case of RB we retrive the flow name of the object (id any)
  and set that as the directory name
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    if media["flow_id"] do
      flow_name =
        Flow
        |> where([f], f.id == ^media["flow_id"])
        |> select([f], f.name)
        |> Repo.one()

      if flow_name in [nil, ""],
        do: media["remote_name"],
        else: flow_name <> "/" <> media["remote_name"]
    else
      media["remote_name"]
    end
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("frappe_check_existing_user", fields) do
    token = fields["token"]
    header = get_header(token)

    url =
      @frappe_open_civic_api_url <>
        "resource/User/" <> fields["contact"]["phone"] <> "@reapbenefit.org"

    Tesla.get(url, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: _body}} ->
        %{is_valid: true, response: "Logged In"}

      {:ok, %Tesla.Env{status: 404, body: body}} ->
        error_msg = Jason.decode!(body)
        %{is_valid: false, response: error_msg["exc_type"]}

      {_status, _response} ->
        %{is_valid: false, response: "Invalid response"}
    end
  end

  def webhook("frappe_create_new_user", fields) do
    token = fields["token"]
    header = get_header(token)

    body =
      %{
        "email" => fields["contact"]["phone"] <> "@reapbenefit.org",
        "first_name" => fields["contact"]["name"]
      }
      |> Jason.encode!()

    url = @frappe_open_civic_api_url <> "resource/User"

    Tesla.post(url, body, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200}} ->
        %{is_valid: true, response: "New User created"}

      {:ok, %Tesla.Env{status: 409}} ->
        %{is_valid: false, response: "Duplicate User"}

      {_status, _response} ->
        %{is_valid: false, response: "Invalid response"}
    end
  end

  def webhook("frappe_add_location", fields) do
    token = fields["token"]
    header = get_header(token)
    body = Jason.encode!(fields)
    url = @frappe_open_civic_api_url <> "resource/Locations"

    Tesla.post(url, body, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200}} ->
        %{is_valid: true, response: "New Location created"}

      {_status, _response} ->
        %{is_valid: false, response: "Invalid response"}
    end
  end

  def webhook(_, _fields), do: %{}

  @spec get_header(String.t()) :: list()
  defp get_header(token) do
    [
      {"Authorization", token},
      {"Content-Type", "application/json"}
    ]
  end
end
