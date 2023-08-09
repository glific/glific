defmodule Glific.Communications.Mailer do
  use Swoosh.Mailer, otp_app: :glific
  import Swoosh.Email

  alias Glific.{
    Mails.MailLog,
    Partners.Organization
  }

  require Logger

  @moduledoc """
  This module provides a simple interface for sending emails.
  """

  @doc """
   Sends an email to the given recipient.
  """
  @spec send(Swoosh.Email.t(), map()) :: {:ok, term} | {:error, term}
  def send(mail, %{category: _category, organization_id: _organization_id} = attrs) do
    ## We will do all the validation here.
    deliver(mail)
    |> capture_log(mail, attrs)
  end

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:swoosh, _action, event], _measurement, meta, _config)
      when event in [:exception] do
    Logger.error("Error while sending the mail: #{inspect(meta)}")
  end

  def handle_event(_, _, _, _), do: nil

  @doc """
  Default sender for all the emails
  """
  @spec sender() :: tuple()
  def sender do
    {"Glific Team", "glific-team@coloredcow.com"}
  end

  @doc """
  Support CC for all the emails
  """
  @spec glific_support() :: tuple()
  def glific_support do
    {"Glific support", "mohit@coloredcow.in"}
  end

  @doc """
  All notification differ only in subject and content,
  Lets write a common function and centralize notification
  code
  """
  @spec common_send(Organization.t(), String.t(), String.t(), [{atom(), any()}]) ::
          Swoosh.Email.t()
  def common_send(org, subject, body, opts \\ []) do
    team = Keyword.get(opts, :team, nil)
    send_to = Keyword.get(opts, :send_to, nil)
    in_cc = Keyword.get(opts, :in_cc, [])
    from_email = Keyword.get(opts, :from_email, sender())

    # Subject can not have a line break
    subject = String.replace(subject, "\n", "")

    send_to = get_team_email(org, team, send_to)

    in_cc = in_cc ++ [glific_support()]

    new()
    |> to(send_to)
    |> from(from_email)
    |> cc(in_cc)
    |> subject(subject)
    |> text_body(body)
  end

  @spec get_team_email(Organization.t(), String.t() | nil, tuple | nil) :: tuple()
  defp get_team_email(org, _team, nil), do: {org.name, org.email}

  defp get_team_email(_org, team, send_to) when team in [nil, ""], do: send_to

  defp get_team_email(org, team, _send_to) do
    org.team_emails
    |> Jason.decode!()
    |> Map.get(team)
    |> then(&{team, &1})
  end

  defp capture_log(
         {:ok, results},
         mail,
         %{category: category, organization_id: organization_id} = _attrs
       ) do
    {:ok, _} =
      %{
        category: category,
        organization_id: organization_id,
        status: "sent",
        content: %{data: "#{inspect(Map.from_struct(mail))}"}
      }
      |> MailLog.create_mail_log()

    {:ok, results}
  end

  defp capture_log(
         {:error, error},
         mail,
         %{category: category, organization_id: organization_id} = _attrs
       ) do
    {:ok, _} =
      %{
        category: category,
        organization_id: organization_id,
        status: "error",
        content: %{data: "#{inspect(Map.from_struct(mail))}"},
        error: "error while sending the mail. #{inspect(error)}"
      }
      |> MailLog.create_mail_log()

    {:error, error}
  end
end
