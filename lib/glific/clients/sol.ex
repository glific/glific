defmodule Glific.Clients.Sol do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Sheets.ApiClient,
    Partners,
    Partners.OrganizationData,
    Repo
  }

  @doc """
  In the case of SOL we retrive the name of the contact is in and store
  and set the remote name to be a sub-directory under that name
  We add a contact id suffix to prevent name collisions
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    contact = Contacts.get_contact!(media["contact_id"])
    city = get_in(contact.fields, ["city", "value"]) || "unknown_city"
    school_name = get_in(contact.fields, ["school_name", "value"]) || "unknown_school_name"
    student_name = get_in(contact.fields, ["contact_name", "value"]) || "unknown_student_name"

    organization_name =
      get_in(contact.fields, ["organization_name", "value"]) || "unknown_organization_name"

    folder = "#{city}/#{school_name}/#{student_name}"
    file_name = "#{contact.phone}_#{city}_#{organization_name}_#{student_name}.png"

    "#{folder}/#{file_name}"
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("fetch_activity", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    language_label = fields["language_label"]
    activity = get_activity_by_date(organization_id, "2022-01-13")
    activity_data = get_activity_content(activity, language_label, organization_id)
    %{completed: true}
  end

  def webhook("load_schedule", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    load_activity_schedule(organization_id)
    %{completed: true}
  end

  @spec webhook(String.t(), map()) :: map()
  def webhook("load_language_activities", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    organization = Partners.organization(organization_id)

    Enum.each(organization.languages, fn language ->
      language.label
      |> String.downcase()
      |> load_language_activities(organization_id)
    end)

    %{completed: true}
  end

  defp load_activity_schedule(org_id) do
    {key, url} = form_key_and_url("activity_schedule")

    ApiClient.get_csv_content(url: url)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      activity_slug = Glific.string_clean(row["Activity name in English"])
      row = Map.put(row, "activity_slug", activity_slug)
      Map.put(acc, row["Date"], row)
    end)
    |> then(fn activity_schedule ->
      Partners.maybe_insert_organization_data(key, activity_schedule, org_id)
    end)
  end

  defp load_language_activities(language_label, org_id) do
    {key, url} = form_key_and_url("activities_#{language_label}")

    ApiClient.get_csv_content(url: url)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      activity_slug = Glific.string_clean(row["Name of the Activity"])
      row = Map.put(row, "activity_slug", activity_slug)
      Map.put(acc, activity_slug, row)
    end)
    |> then(fn activity_data ->
      Partners.maybe_insert_organization_data(key, activity_data, org_id)
    end)
  end

  defp form_key_and_url(key) do
    key = "sol_#{key}"
    url = "https://storage.googleapis.com/sheet-automation/#{key}.csv"
    {key, url}
  end

  def get_activity_by_date(organization_id, date) do
    {key, _url} = form_key_and_url("activity_schedule")

    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: key
      })

    Map.get(org_data.json, date)
  end

  def get_activity_content(activity, language_label, organization_id) do
    language_label = String.downcase(language_label)
    {key, _url} = form_key_and_url("activities_#{language_label}")

    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: key
      })

    activity_content = Map.get(org_data.json, activity["activity_slug"])

    %{
      name: activity_content["Name of the Activity"],
      artform: activity_content["Type of Activity"],
      content: activity_content["Content of the Activty"],
      poster_attachment: activity_content["Poster GCS Link"],
      audio_attachment: activity_content["Audio Recording GCS Link"]
    }
  end
end
