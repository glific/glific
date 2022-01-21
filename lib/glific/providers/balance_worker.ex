defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking remaining balance
  """

  alias Glific.{
    Communications,
    Communications.Mailer,
    Mails.LowBalanceAlertMail,
    Mails.MailLog,
    Partners
  }

  require Logger

  @doc """
  periodic function for making calls to bsp for remaining balance
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    Logger.info("Checking BSP balance: organization_id: '#{organization_id}'")

    Partners.get_bsp_balance(organization_id)
    |> case do
      {:ok, data} ->
        bsp_balance = data["balance"]

        send_low_balance_notification(bsp_balance, organization_id)

        # We should move this to an embedded schema
        # and then fix the function in publish_data. Basically have a periodic
        # status message packet sent to frontend with this and other details
        Communications.publish_data(
          %{"balance" => bsp_balance},
          :bsp_balance,
          organization_id
        )

      _ ->
        nil
    end

    :ok
  end

  @spec send_low_balance_notification(integer(), non_neg_integer()) :: nil | {:ok, any}
  defp send_low_balance_notification(bsp_balance, organization_id) when bsp_balance < 1 do
    ## We need to check if we have already sent this notification in last 24 hours
    category = "low_bsp_balance"
    time = Glific.go_back_time(24)

    if MailLog.mail_sent_in_past_time?(category, time, organization_id) == false do
      {:ok, _} =
        Partners.organization(organization_id)
        |> LowBalanceAlertMail.new_mail(bsp_balance)
        |> Mailer.send(%{
          category: category,
          organization_id: organization_id
        })
    else
      {:ok, "no email"}
    end
  end

  defp send_low_balance_notification(_, _), do: nil
end
