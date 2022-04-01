defmodule Glific.Mails.BalanceAlertMail do
  @moduledoc """
  This module is used to send an email to the user when their balance is low.
  """
  alias Glific.{Communications.Mailer, Partners.Organization}

  @doc false
  @spec low_balance_alert(Organization.t(), integer()) :: Swoosh.Email.t()
  def low_balance_alert(org, bsp_balance) do
    subject = """
    Glific Alert: Your Gupshup balance is low.
    """

    body = """
    Your balance is low $#{bsp_balance}.

    Please top up your account to keep sending and receiving messages on Glific."
    """

    Mailer.common_send(org, subject, body)
  end

  @doc false
  @spec no_balance(Organization.t(), String.t()) :: Swoosh.Email.t()
  def no_balance(org, body) do
    subject = """
    Glific Critical: Your Gupshup balance is zero, please refill immediately.
    """

    Mailer.common_send(org, subject, body)
  end

  @doc false
  @spec rate_exceeded(Organization.t(), String.t()) :: Swoosh.Email.t()
  def rate_exceeded(org, body) do
    subject = """
    Glific Critical: Your organization has exceeded it WhatsApp rate limit.
    """

    Mailer.common_send(org, subject, body)
  end
end
