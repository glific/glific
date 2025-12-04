defmodule Glific.Mails.GupshupSetupMail do
  @moduledoc """
  This module is used to send Gupshup setup completion emails to support team.
  """

  alias Glific.Communications.Mailer
  alias Glific.Partners.Organization

  @doc """
  Send a Gupshup setup completion email to the support team.
  """
  @spec send_gupshup_setup_completion_mail(Organization.t()) :: {:ok, any()} | {:error, any()}
  def send_gupshup_setup_completion_mail(organization) do
    subject = "Gupshup Setup Completed - #{organization.name}"

    body = """
    A new organization has configured their Gupshup credentials.

    Organization Details:
    - Name: #{organization.name}
    - Shortcode: #{organization.shortcode}

    Please reach out to the organization if needed.
    """

    Mailer.common_send(
      nil,
      subject,
      body,
      send_to: Mailer.glific_support()
    )
    |> Mailer.send(%{
      category: "Gupshup Setup",
      organization_id: organization.id
    })
  end
end
