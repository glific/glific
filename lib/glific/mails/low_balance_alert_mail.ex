defmodule Glific.Mails.LowBalanceAlertMail do
  @moduledoc """
  This module is used to send an email to the user when their balance is low.
  """

  import Swoosh.Email
  alias Glific.Communications.Mailer

  @spec new_mail(map(), integer()) :: Swoosh.Email.t()
  def new_mail(org, bsp_balance) do
    new()
    |> to({org.name, org.email})
    |> from(Mailer.sender())
    |> cc(Mailer.glific_support())
    |> subject("Gupshup balance is low.")
    |> text_body(
      "Your balance is low $#{bsp_balance}. Please top up your account to keep sending the messages."
    )
  end
end
