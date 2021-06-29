defmodule Glific.Clients.DigitalGreen do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any)
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Groups,
    Groups.Group,
    Repo
  }

  @stage_1 "Stage 1"
  @stage_2 "Stage 2"
  @stage_3 "Stage 3"

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("daily", fields) do
    {:ok, contact_id} = Glific.parse_maybe_integer(fields["contact_id"])
    {:ok, organization_id} = Glific.parse_maybe_integer(fields["organization_id"])

    enrolled_date = format_date(fields["contact"]["fields"]["enrolled_day"]["value"])

    number_of_days = Timex.now() |> Timex.diff(enrolled_date, :days)

    next_flow = fields["contact"]["fields"]["next_flow"]["value"]

    next_flow_at =
      fields["contact"]["fields"]["next_flow_at"]["value"]
      |> format_date

    move_to_group(number_of_days, contact_id, organization_id)

    add_to_next_flow_group(
      next_flow,
      next_flow_at,
      contact_id,
      organization_id
    )

    fields
  end

  def webhook(_, _fields),
    do: %{}

  @spec move_to_group(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok
  defp move_to_group(2, contact_id, organization_id) do
    with {:ok, stage_one_group} <-
           Repo.fetch_by(Group, %{label: @stage_1, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_two_group.id,
        organization_id: organization_id
      })

      Groups.delete_group_contacts_by_ids(stage_one_group.id, [contact_id])
    end

    :ok
  end

  defp move_to_group(4, contact_id, organization_id) do
    with {:ok, stage_three_group} <-
           Repo.fetch_by(Group, %{label: @stage_3, organization_id: organization_id}),
         {:ok, stage_two_group} <-
           Repo.fetch_by(Group, %{label: @stage_2, organization_id: organization_id}) do
      Groups.create_contact_group(%{
        contact_id: contact_id,
        group_id: stage_three_group.id,
        organization_id: organization_id
      })

      Groups.delete_group_contacts_by_ids(stage_two_group.id, [contact_id])
    end

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
