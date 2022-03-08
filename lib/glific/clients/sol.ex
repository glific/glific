defmodule Glific.Clients.Sol do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient
  }

  @doc """
  In the case of SOL we retrive the name of the contact is in and store
  and set the remote name to be a sub-directory under that name
  We add a contact id suffix to prevent name collisions
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    {:ok, contact} =
      Repo.fetch_by(Contacts.Contact, %{
        id: media["contact_id"],
        organization_id: media["organization_id"]
      })

    message_media = Glific.Messages.get_message_media!(media["id"])

    city = get_in(contact.fields, ["city", "value"]) || "unknown_city"
    _school_name = get_in(contact.fields, ["school_name", "value"]) || "unknown_school_name"
    student_name = get_in(contact.fields, ["contact_name", "value"]) || "unknown_student_name"
    caption = message_media.caption || ""

    _organization_name =
      get_in(contact.fields, ["organization_name", "value"]) || "unknown_organization_name"

    current_time = :os.system_time(:millisecond)

    folder = "#{city}/#{contact.phone}/#{student_name}"

    extension = get_extension(media["type"])

    file_name = "#{contact.phone}_#{city}_#{student_name}_#{caption}_#{current_time}.#{extension}"

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
    city = fields["city"]
    ## y-m-d
    activity_date = Timex.today() |> Timex.format!("{YYYY}-{0M}-{0D}")
    activity = get_activity_by_date(organization_id, activity_date, city)
    activity_data = get_activity_content(activity, language_label, organization_id)

    activity_data =
      Map.merge(
        activity_data,
        %{
          city: city,
          activity_date: activity_date,
          artform_lable: "artform_start_#{activity_data[:artform]}_artform_ended",
          activity_name_label: "activity_name_start_#{activity_data[:name]}_activity_name_ended"
        }
      )

    if activity_data[:content] in [nil, ""],
      do: Map.put(activity_data, :error, "Something went worng."),
      else: Map.put(activity_data, :error, false)
  end

  def webhook("load_schedule", fields) do
    organization_id = Glific.parse_maybe_integer!(fields["organization_id"])
    load_activity_schedule(organization_id)
    %{completed: true}
  end

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

  @spec load_activity_schedule(non_neg_integer()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
  def load_activity_schedule(org_id) do
    {key, url} = form_key_and_url("activity_schedule")

    ApiClient.get_csv_content(url: url)
    |> Enum.reduce(%{}, fn {_, row}, acc ->
      activity_slug = Glific.string_clean(row["Activity name in English"])
      row = Map.put(row, "activity_slug", activity_slug)
      date = row["Date"]
      city = row["City"]

      if Map.has_key?(acc, date),
        do: Map.put(acc, date, Map.put(acc[date], city, row)),
        else: Map.put(acc, date, Map.put(%{}, city, row))
    end)
    |> then(fn activity_schedule ->
      Partners.maybe_insert_organization_data(key, activity_schedule, org_id)
    end)
  end

  @spec load_language_activities(String.t(), non_neg_integer()) ::
          {:ok, OrganizationData.t()} | {:error, Ecto.Changeset.t()}
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

  @spec form_key_and_url(String.t()) :: {String.t(), String.t()}
  defp form_key_and_url(key) do
    key = "sol_#{key}"
    url = "https://storage.googleapis.com/sheet-automation/#{key}.csv"
    {key, url}
  end

  @spec get_activity_by_date(non_neg_integer(), String.t(), String.t()) :: map()
  defp get_activity_by_date(organization_id, date, city) do
    {key, _url} = form_key_and_url("activity_schedule")

    {:ok, org_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: organization_id,
        key: key
      })

    get_in(org_data.json, [date, city])
  end

  @spec get_activity_content(map(), String.t(), non_neg_integer()) :: map()
  defp get_activity_content(activity, language_label, organization_id) do
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
      audio_attachment: activity_content["Audio Recording GCS Link"],
      activity_meta: activity,
      activity_slug: activity["activity_slug"]
    }
  end

  defp get_extension(type) do
    cond do
      type in ["audio"] -> "mp3"
      type in ["video"] -> "mp4"
      type in ["image"] -> "png"
      type in ["document"] -> "pdf"
      true -> "png"
    end
  end
end
