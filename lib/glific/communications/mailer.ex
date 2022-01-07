defmodule Glific.Communications.Mailer do
  use Swoosh.Mailer, otp_app: :glific

  @moduledoc """
  This module provides a simple interface for sending emails.
  """

  @doc """
  Default sender for all the emails
  """
  @spec sender() :: tuple()
  def sender do
    {"Glific Team", "glific-tides-support@coloredcow.com"}
  end
end
