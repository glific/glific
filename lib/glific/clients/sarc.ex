defmodule Glific.Clients.Sarc do
  @moduledoc """
  Tweak GCS Bucket name based on group that the contact is in (if any) for SArC
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Repo
  }

  @acp_submission_flow_id 26_384

  @doc """
  Generate custom GCS bucket name based on group that the contact is in (if any)
  """
  @spec gcs_file_name(map()) :: String.t()
  def gcs_file_name(%{"contact_id" => contact_id} = media) when is_nil(contact_id),
    do: media["remote_name"]

  def gcs_file_name(%{"flow_id" => flow_id} = media) when flow_id == @acp_submission_flow_id do
    Contacts.Contact
    |> Repo.fetch_by(%{
      id: media["contact_id"],
      organization_id: media["organization_id"]
    })
    |> case do
      {:ok, contact} ->
        org_name = get_in(contact.fields, ["name_of_organization", "value"])

        acp_submission = get_in(contact.fields, ["acp_submission", "value"])

        name_of_educator = get_in(contact.fields, ["name_of_educator", "value"])

        generate_filename(media["remote_name"], [org_name, acp_submission, name_of_educator])

      {:error, _} ->
        media["remote_name"]
    end
  end

  def gcs_file_name(media), do: media["remote_name"]

  # We need the ending part of the file name to be educator name
  @spec generate_filename(String.t(), list()) :: String.t()
  defp generate_filename(remote_name, contact_fields) do
    if Enum.any?(contact_fields, &is_nil/1) do
      remote_name
    else
      [org_name, acp_submission, name_of_educator] = contact_fields
      url = "acp_submissions_2425/#{org_name}/#{acp_submission}/"
      [message_name, ext] = String.split(remote_name, ".")
      url <> message_name <> "_" <> name_of_educator <> "." <> ext
    end
  end
end
