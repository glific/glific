defmodule Glific.Communications.Mailer do
  use Swoosh.Mailer, otp_app: :glific

  @doc """
  Default sender for all the emails
  """
  @spec sender() :: tuple()
  def sender() do
    {"Pankaj Agrawal", "glific-tides-support@coloredcow.com"}
  end
end
