defmodule Glific.Clients.DigitalGreenJharkhand do
  @moduledoc """
  Custom webhook implementation specific to DigitalGreen Jharkhand usecase
  """
  alias Glific.{
    Partners.OrganizationData,
    Repo
  }

  @doc """
  Create a webhook with different signatures, so we can easily implement
  additional functionality as needed
  """
  @spec webhook(String.t(), map()) :: map()
  def webhook("push_crop_calendar_message", fields) do
    crop_age = fields["crop_age"]

    {:ok, organization_data} =
      Repo.fetch_by(OrganizationData, %{
        organization_id: fields["organization_id"],
        key: fields["crop"]
      })

    template_uuid = get_in(organization_data.json, [crop_age, "template_uuid"])
    variables = get_in(organization_data.json, [crop_age, "variables"])
    crop_stage = get_in(organization_data.json, [crop_age, "crop_stage"])
    media_url = get_in(organization_data.json, [crop_age, "media_url"])
    crop_stage_eng = get_in(organization_data.json, [crop_age, "crop_stage_eng"])

    if template_uuid,
      do: %{
        is_valid: true,
        template_uuid: template_uuid,
        crop_stage: crop_stage,
        variables: Jason.encode!(variables),
        media_url: media_url,
        crop_age: crop_age,
        crop_stage_eng: crop_stage_eng,
        organization_id: fields["organization_id"]
      },
      else: %{is_valid: false}
  end

  def webhook(_, _fields),
    do: %{}
end
