defmodule Glific.Clients.Tap do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts.Contact,
    Groups.ContactGroup,
    Groups.Group,
    Partners,
    Partners.OrganizationData,
    Repo,
    Sheets.ApiClient,
    Templates.SessionTemplate
  }

  @props %{
    sheet_links: %{
      activity:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vR-GBWadR2F3QKZ43jaUwS9WYy0QQ5n_AMW4FN5AziwrEuNcfFr5__5zsO1nMNX04M1BmvChBaXTU9r/pub?gid=2079471637&single=true&output=csv",
      quiz:
        "https://docs.google.com/spreadsheets/d/e/2PACX-1vR-GBWadR2F3QKZ43jaUwS9WYy0QQ5n_AMW4FN5AziwrEuNcfFr5__5zsO1nMNX04M1BmvChBaXTU9r/pub?gid=720505613&single=true&output=csv"
    }
  }

  @doc """
  In the case of TAP we retrive the first group the contact is in and store
  and set the remote name to be a sub-directory under that group (if one exists)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(media) do
    group_name =
      Contact
      |> where([c], c.id == ^media["contact_id"])
      |> join(:inner, [c], cg in ContactGroup, on: c.id == cg.contact_id)
      |> join(:inner, [_c, cg], g in Group, on: cg.group_id == g.id)
      |> select([_c, _cg, g], g.label)
      |> order_by([_c, _cg, g], g.label)
      |> first()
      |> Repo.one()

    if is_nil(group_name),
      do: media["remote_name"],
      else: group_name <> "/" <> media["remote_name"]
  end

  @doc """
  get template form EEx without variables
  """
  @spec template(String.t(), String.t()) :: binary
  def template(shortcode, params_staring \\ "") do
    {:ok, template} = Repo.fetch_by(SessionTemplate, %{shortcode: shortcode})

    %{
      uuid: template.uuid,
      name: "Template",
      expression: nil,
      variables: parse_template_vars(template, params_staring)
    }
    |> Jason.encode!()
  end

  defp parse_template_vars(template, params_staring) do
    params = String.split(params_staring || "", "|", trim: true)

    if length(params) == template.number_parameters do
      params
    else
      params_with_missing =
        params ++ Enum.map(1..template.number_parameters, fn _i -> "{{ missing var  }}" end)

      Enum.take(params_with_missing, template.number_parameters)
    end
  end

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("load_activities", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_activities()

    fields
  end

  def webhook("load_quizes", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> load_quizes()

    fields
  end

  def webhook("get_activity_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_activity_info(fields["date"], fields["type"])
  end

  def webhook("get_quiz_info", fields) do
    Glific.parse_maybe_integer!(fields["organization_id"])
    |> get_quiz_info(fields["activity_id"])
  end

  def webhook(_, fields), do: fields

  @spec load_activities(non_neg_integer()) :: :ok
  defp load_activities(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.activity)
    |> Enum.each(fn {_, row} ->
      key = "schedule_" <> row["Schedule"]
      activity_type = Glific.string_clean(row["Activity type"])
      info = %{activity_type => row}
      Partners.maybe_insert_organization_data(key, info, org_id)
    end)
  end

  @spec load_quizes(non_neg_integer()) :: :ok
  defp load_quizes(org_id) do
    ApiClient.get_csv_content(url: @props.sheet_links.quiz)
    |> Enum.each(fn {_, row} ->
      IO.inspect(row["Activity"])
      question_key = Glific.string_clean(row["Question"])
      key = "quiz_" <> row["Activity"] <> "_" <> question_key
      Partners.maybe_insert_organization_data(key, row, org_id)
    end)
  end

  @spec get_activity_info(non_neg_integer(), String.t(), String.t()) :: map()
  defp get_activity_info(org_id, date, type) do
    Repo.fetch_by(OrganizationData, %{
      organization_id: org_id,
      key: "schedule_" <> date
    })
    |> case do
      {:ok, data} ->
        data.json[type]
        |> clean_map_keys()
        |> Map.merge(%{
          is_valid: true,
          message: "Activity found"
        })

      _ ->
        %{
          is_valid: false,
          message: "Worksheet code not found"
        }
    end
  end

  @spec get_quiz_info(non_neg_integer(), String.t()) :: map()
  defp get_quiz_info(org_id, activity_id) do
    quizes =
      Partners.list_organization_data(%{
        organization_id: org_id,
        filter: %{
          key: "quiz_" <> activity_id
        }
      })

    %{quizes: quizes}
  end

  @spec clean_map_keys(map()) :: map()
  defp clean_map_keys(data) do
    data
    |> Enum.map(fn {k, v} -> {Glific.string_clean(k), v} end)
    |> Enum.into(%{})
  end
end
