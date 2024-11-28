defmodule GlificWeb.Providers.Maytapi.Controllers.MessageEventController do
  @moduledoc """
  Dedicated controller to handle all the message status requests like sent, delivered etc..
  """
  use GlificWeb, :controller
  use Publicist

  alias Glific.{
    Communications,
    Repo
  }

  @message_event_type %{
    "delivered" => :delivered,
    "reached" => :reached,
    "seen" => :seen,
    # for sound messages
    "played" => :played,
    "deleted" => :deleted
  }

  @doc """
  Default handle for all message event callbacks
  """
  @spec handler(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handler(conn, params) do
    Task.Supervisor.start_child(Glific.TaskSupervisor, fn ->
      Repo.put_process_state(conn.assigns.organization_id)
      update_statuses(params, conn.assigns.organization_id)
    end)

    json(conn, nil)
  end

  @spec update_statuses(map(), non_neg_integer()) :: any()
  defp update_statuses(%{"data" => response} = _params, org_id) do
    response
    |> Enum.each(fn item ->
      if Map.has_key?(item, "reaction") do
        reaction(item, org_id)
      else
        do_update_status(item, item["ackType"], org_id)
      end
    end)
  end

  @spec reaction(map(), non_neg_integer()) :: any()
  defp reaction(params, org_id) do
    params
    |> Communications.GroupMessage.receive_reaction_msg(org_id)
  end

  # Updates the provider message statuses based on provider message id
  @spec do_update_status(map(), String.t(), non_neg_integer()) :: any()
  defp do_update_status(params, ack_type, org_id) do
    status = Map.get(@message_event_type, ack_type)
    bsp_message_id = Map.get(params, "msgId")
    Communications.GroupMessage.update_bsp_status(bsp_message_id, status, org_id)
  end
end
