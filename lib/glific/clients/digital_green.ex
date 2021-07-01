defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Flows.ContactField,
    Groups,
    Groups.Group,
    Navanatech,
    Repo
  }

  @stage_1 "Stage 1"
  @stage_2 "Stage 2"
  @stage_3 "Stage 3"
  @stage_1_threshold 26
  @stage_2_threshold 40
  @stage_3_threshold 60

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])

    {:ok, initial_crop_day} =
      Glific.parse_maybe_integer(fields["contact"]["fields"]["initial_crop_day"]["value"])

    enrolled_date = format_date(fields["contact"]["fields"]["enrolled_day"]["value"])
    days_since_enrolled = Timex.now() |> Timex.diff(enrolled_date, :days)
    total_days = days_since_enrolled + initial_crop_day

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("total_days", "total_days", total_days, "string")

    next_flow = fields["contact"]["fields"]["next_flow"]["value"]

    next_flow_at =
      fields["contact"]["fields"]["next_flow_at"]["value"]
      |> format_date

    move_to_group(total_days, contact_id, organization_id)

    add_to_next_flow_group(
      next_flow,
      next_flow_at,
      contact_id,
      organization_id
    )

    fields
  end

  def webhook("crop_stage", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    update_crop_days(fields["crop_stage"], contact_id)
    fields
  end

  def webhook("navanatech", fields) do
    Navanatech.navatech_post(fields)
  end

  def webhook(_, _fields),
    do: %{}

  defp update_crop_days(@stage_1, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "17", "string")
  end

  defp update_crop_days(@stage_2, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "33", "string")
  end

  defp update_crop_days(@stage_3, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "50", "string")
  end

  defp update_crop_days(_, contact_id) do
    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("initial_crop_day", "initial_crop_day", "0", "string")
  end

  @spec move_to_group(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  defp move_to_group(0, contact_id, organization_id) do
    {:ok, stage_one_group} =
      Repo.fetch_by(Group, %{label: @stage_1, organization_id: organization_id})

    Groups.create_contact_group(%{
      contact_id: contact_id,
      group_id: stage_one_group.id,
      organization_id: organization_id
    })

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_1, "string")

    :ok
  end

  defp move_to_group(@stage_1_threshold, contact_id, organization_id) do
    with {:ok, stage_one_group} <-
           Repo.fetch_by(Group, %{label: @stage_1, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_two_group.id,
        organization_id: organization_id
      })

      Contacts.get_contact!(contact_id)
      |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_2, "string")

      Groups.delete_group_contacts_by_ids(stage_one_group.id, [contact_id])
    end

    :ok
  end

  defp move_to_group(@stage_2_threshold, contact_id, organization_id) do
    with {:ok, stage_three_group} <-
           Repo.fetch_by(Group, %{label: @stage_3, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_three_group.id,
        organization_id: organization_id
      })

      Contacts.get_contact!(contact_id)
      |> ContactField.do_add_contact_field("crop_stage", "crop_stage", @stage_3, "string")

      Groups.delete_group_contacts_by_ids(stage_two_group.id, [contact_id])
    end

    :ok
  end

  defp move_to_group(@stage_3_threshold, contact_id, organization_id) do
    {:ok, stage_three_group} =
      Repo.fetch_by(Group, %{label: @stage_3, organization_id: organization_id})

    Contacts.get_contact!(contact_id)
    |> ContactField.do_add_contact_field("crop_stage", "crop_stage", "completed", "string")

    Groups.delete_group_contacts_by_ids(stage_three_group.id, [contact_id])

    :ok
  end

  defp move_to_group(_, _contact_id, _organization_id), do: :ok

  @spec add_to_next_flow_group(String.t(), Date.t(), non_neg_integer(), non_neg_integer()) :: :ok
  defp add_to_next_flow_group(next_flow, next_flow_at, contact_id, organization_id) do
    with 0 <- Timex.diff(Timex.now(), next_flow_at, :days),
         {:ok, next_flow_group} <-
           Repo.fetch_by(Group, %{label: next_flow, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: next_flow_group.id,
        organization_id: organization_id
      })
    end

    :ok
  end

  @spec format_date(String.t()) :: Date.t()
  defp format_date(date) do
    date
    |> Timex.parse!("{YYYY}-{0M}-{D}")
    |> Timex.to_date()
  end
end
