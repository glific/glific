defmodule Glific.Jobs.BSPBalanceWorker do
  @moduledoc """
  Module for checking remaining balance
  """

  alias Glific.{
    Communications,
    Communications.Mailer,
    Mails.BalanceAlertMail,
    Mails.MailLog,
    Partners,
    Partners.Organization,
    Repo
  }

  require Logger

  @doc """
  periodic function for making calls to bsp for remaining balance
  """
  @spec perform_periodic(non_neg_integer) :: :ok
  def perform_periodic(organization_id) do
    organization = Repo.get!(Organization, organization_id)
    threshold = organization.setting.low_balance_threshold
    critical_balance_threshold = organization.setting.critical_balance_threshold

    Logger.info("Checking BSP balance: organization_id: '#{organization_id}'")

    Partners.get_bsp_balance(organization_id)
    |> case do
      {:ok, data} ->
        bsp_balance = data["balance"]

        send_low_balance_notification(
          bsp_balance,
          organization_id,
          threshold,
          critical_balance_threshold
        )

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

  @spec send_low_balance_notification(
          integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          nil | {:ok, any}
  defp send_low_balance_notification(bsp_balance, organization_id, nil, nil),
    do: send_low_balance_notification(bsp_balance, organization_id, 10, 3)

  defp send_low_balance_notification(
         bsp_balance,
         organization_id,
         threshold,
         critical_balance_threshold
       )
       when bsp_balance < threshold do
    # start sending a warning message when the balance is lower than a certain threshold default is $10
    # we can tweak this over time
    # If the balance is below a certain threshold or it's critically low (below $3 by default), trigger a warning notification.
    go_back = if bsp_balance < critical_balance_threshold, do: 48, else: 7 * 24

    ## We need to check if we have already sent this notification in last go_back time
    category = "low_bsp_balance"
    time = Glific.go_back_time(go_back)

    if MailLog.mail_sent_in_past_time?(category, time, organization_id) == false do
      {:ok, _} =
        Partners.organization(organization_id)
        |> BalanceAlertMail.low_balance_alert(bsp_balance)
        |> Mailer.send(%{
          category: category,
          organization_id: organization_id
        })
    else
      {:ok, "no email"}
    end
  end

  defp send_low_balance_notification(_, _, _, _), do: nil
end
