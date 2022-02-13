defmodule Glific.Mails.LowBalanceAlertMail do
  @moduledoc """
  This module is used to send an email to the user when their balance is low.
  """
  alias Glific.Communications.Mailer

  @spec new_mail(map(), integer()) :: Swoosh.Email.t()
  def new_mail(org, bsp_balance) do
    subject = """
    Glific Alert: Your Gupshup balance is low.
    """

    body = """
    Your balance is low $#{bsp_balance}.

    Please top up your account to keep sending and receiving messages on Glific."
    """

    Mailer.common_send(org, subject, body)
  end
end
