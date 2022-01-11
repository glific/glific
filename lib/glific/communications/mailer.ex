defmodule Glific.Communications.Mailer do
  use Swoosh.Mailer, otp_app: :glific

  @moduledoc """
  This module provides a simple interface for sending emails.
  """

  @doc """
   Sends an email to the given recipient.
  """
  @spec send(Swoosh.Email.t(), Keyword.t()) :: {:ok, term} | {:error, term}
  def send(mail, _config \\ []) do
    IO.inspect("mail")
    IO.inspect(mail)
    ## We will do all the validation here.
    deliver(mail)
  end

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:swoosh, _action, event], measurement, meta, config)
      when event in [:stop, :exception] do
    # IO.inspect(meta)
  end

  def handle_event(_, _, _, _), do: nil

  @doc """
  Default sender for all the emails
  """
  @spec sender() :: tuple()
  def sender do
    {"Glific Team", "glific-tides-support@coloredcow.com"}
  end
end
