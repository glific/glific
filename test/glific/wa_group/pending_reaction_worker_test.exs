defmodule Glific.WAGroup.PendingReactionWorkerTest do
  use Glific.DataCase
  use Oban.Testing, repo: Glific.Repo, prefix: "global"

  import Ecto.Query

  alias Glific.{
    Communications.GroupMessage,
    Fixtures,
    Repo,
    WAGroup.PendingReactionWorker,
    WAGroup.WaReaction
  }

  @group_bsp_id "120363238104@g.us"
  @parent_api_id "b7c1d2e3-c710-11ee-a8e7-5fbaaf152c1d"
  @parent_whatsapp_id "true_#{@group_bsp_id}_3EB0C0FFEE0000000002_917834811114@c.us"

  @reaction_params %{
    "reactorId" => "919812345678",
    "reaction" => "👍",
    "msgId" => @parent_whatsapp_id,
    "reactionId" => "false_#{@group_bsp_id}_AC1B50CEE745CF9602ABBD26BD8062B3_919812345678@c.us"
  }

  setup %{organization_id: organization_id} do
    wa_managed_phone = Fixtures.get_wa_managed_phone(organization_id)

    wa_group =
      Fixtures.wa_group_fixture(%{
        organization_id: organization_id,
        wa_managed_phone_id: wa_managed_phone.id,
        bsp_id: @group_bsp_id
      })

    parent_message =
      Fixtures.wa_message_fixture(%{
        organization_id: organization_id,
        wa_group_id: wa_group.id,
        flow: :outbound,
        bsp_id: @parent_api_id
      })

    %{parent_message: parent_message}
  end

  defp reactions_for(wa_message_id) do
    WaReaction
    |> where([wa_reaction], wa_reaction.wa_message_id == ^wa_message_id)
    |> Repo.all()
  end

  defp job_args(organization_id, retry),
    do: %{reaction: @reaction_params, organization_id: organization_id, retry: retry}

  test "a reaction that arrives before the delivery ack is saved on retry",
       %{organization_id: organization_id, parent_message: parent_message} do
    assert {:error, :not_found} =
             GroupMessage.receive_reaction_msg(@reaction_params, organization_id)

    assert_enqueued(worker: PendingReactionWorker, args: job_args(organization_id, 0))

    GroupMessage.update_bsp_status(
      @parent_api_id,
      :delivered,
      organization_id,
      @parent_whatsapp_id
    )

    assert :ok = perform_job(PendingReactionWorker, job_args(organization_id, 0))
    assert [%WaReaction{reaction: "👍"}] = reactions_for(parent_message.id)
  end

  test "schedules the next retry while the parent message is still missing",
       %{organization_id: organization_id, parent_message: parent_message} do
    assert {:ok, _job} = PendingReactionWorker.enqueue(@reaction_params, organization_id)
    assert :ok = perform_job(PendingReactionWorker, job_args(organization_id, 0))

    assert_enqueued(worker: PendingReactionWorker, args: job_args(organization_id, 1))
    assert [] == reactions_for(parent_message.id)
  end

  test "the same reaction failing more than once starts a single retry chain",
       %{organization_id: organization_id} do
    assert {:error, :not_found} =
             GroupMessage.receive_reaction_msg(@reaction_params, organization_id)

    assert {:error, :not_found} =
             GroupMessage.receive_reaction_msg(@reaction_params, organization_id)

    assert [_job] = all_enqueued(worker: PendingReactionWorker)
  end

  test "a reaction without a parent message id is skipped without a retry",
       %{organization_id: organization_id} do
    assert {:error, :missing_parent_id} =
             @reaction_params
             |> Map.put("msgId", nil)
             |> GroupMessage.receive_reaction_msg(organization_id)

    refute_enqueued(worker: PendingReactionWorker)
  end

  test "gives up after the last retry",
       %{organization_id: organization_id, parent_message: parent_message} do
    assert :ok = perform_job(PendingReactionWorker, job_args(organization_id, 2))

    refute_enqueued(worker: PendingReactionWorker)
    assert [] == reactions_for(parent_message.id)
  end
end
