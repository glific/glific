defmodule Glific.Clients.ReapBenefit do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Flows.Flow,
    Repo
  }

  @frappe_open_civic_api_url "http://frappe.solveninja.org/api/resource/"
  @frappe_open_civic_location_api "http://frappe.solveninja.org/api/method/open_civic_backend.api.location.new"

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

    url = @frappe_open_civic_api_url <> "User/" <> fields["contact"]["phone"] <> "@solveninja.org"

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
        "email" => fields["contact"]["phone"] <> "@solveninja.org ",
        "first_name" => fields["contact"]["name"],
        "mobile_no" => fields["contact"]["phone"],
        "username" => fields["contact"]["name"]
      }
      |> Jason.encode!()

    url = @frappe_open_civic_api_url <> "User"

    Tesla.post(url, body, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> to_minimal_map("User")
        |> Map.merge(%{is_valid: true})

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

    Tesla.post(@frappe_open_civic_location_api, body, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> to_minimal_map("Locations")
        |> Map.merge(%{is_valid: true})

      {_status, _response} ->
        %{is_valid: false, response: "Invalid response"}
    end
  end

  def webhook("frappe_add_event", fields) do
    token = fields["token"]
    header = get_header(token)
    body = Jason.encode!(fields)
    url = @frappe_open_civic_api_url <> "Events"

    Tesla.post(url, body, headers: header)
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Jason.decode!(body)
        |> to_minimal_map("Events")
        |> Map.merge(%{is_valid: true})

      {_status, _response} ->
        %{is_valid: false, response: "Invalid response"}
    end
  end

  def webhook("fetch_from_frappe", fields) do
    with %{is_valid: true, attrs: attrs} <- validate_fetch_attrs(fields) do
      {doctype, doctype_id, token} = attrs
      header = get_header(token)
      url = @frappe_open_civic_api_url <> "#{doctype}/" <> doctype_id

      Tesla.get(url, headers: header)
      |> case do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          Jason.decode!(body)
          |> to_minimal_map(doctype)
          |> Map.merge(%{is_valid: true})

        {:ok, %Tesla.Env{status: 404, body: body}} ->
          error_msg = Jason.decode!(body)

          %{is_valid: false, response: error_msg["exc_type"]}

        {_status, _response} ->
          %{is_valid: false, response: "Invalid response"}
      end
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

  @spec validate_fetch_attrs(map()) :: map()
  defp validate_fetch_attrs(
         %{
           "doctype" => doctype,
           "doctype_id" => doctype_id,
           "token" => token
         } = _fields
       )
       when doctype in ["User", "Locations", "Events", "Assets"] do
    %{is_valid: true, attrs: {doctype, doctype_id, token}}
  end

  defp validate_fetch_attrs(_fields),
    do: %{is_valid: false, message: "Add Doctype, Doctype_id and Token in body to proceed"}

  @spec to_minimal_map(map(), String.t()) :: map()
  defp to_minimal_map(%{"data" => data} = _body, "User"),
    do: Map.take(data, ["name", "email", "first_name", "last_name", "gender", "mobile_no"])

  defp to_minimal_map(%{"message" => message} = _body, "Locations"),
    do: Map.take(message, ["name", "latitude", "longitude", "city", "state", "district"])

  defp to_minimal_map(%{"data" => data} = _body, "Events"),
    do: Map.take(data, ["name", "title", "type", "status", "category", "subcategory"])

  defp to_minimal_map(_data, _doctype), do: %{}
end
