defmodule Glific.Mails.EvalAccessRequestMail do
  @moduledoc """
  Sends an email to the Glific support team when an organization requests
  access to the AI Evaluations feature.
  """

  alias Glific.Communications.Mailer
  alias Glific.Partners.Organization

  @doc """
  Sends a notification to the Glific support team about a new eval access request.
  """
  @spec send_eval_access_request_mail(Organization.t()) :: {:ok, any()} | {:error, any()}
  def send_eval_access_request_mail(organization) do
    subject = "AI Evaluations Access Request - #{organization.name}"

    body = """
    An organization has requested access to the AI Evaluations feature.

    Organization Details:
    - Name: #{organization.name}
    - Shortcode: #{organization.shortcode}
    - Email: #{organization.email}
    - Login URL: https://#{organization.shortcode}.#{Glific.base_domain()}

    Please review and enable the AI Evaluations feature flag for this organization.
    """

    Mailer.common_send(
      nil,
      subject,
      body,
      send_to: Mailer.glific_support()
    )
    |> Mailer.send(%{
      category: "AI Evaluations Access Request",
      organization_id: organization.id
    })
  end
end
