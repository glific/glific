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
    ## We will do all the validation here.
    deliver(mail)
  end

  @doc false
  @spec handle_event(list(), any(), any(), any()) :: any()
  def handle_event([:swoosh, _action, event], _measurement, _meta, _)
      when event in [:stop, :exception] do
    # Will logs the emails here.
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
