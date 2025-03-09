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
  defp update_statuses(%{"type" => "error"} = params, org_id) do
    do_update_error_status(params, org_id)
  end

  defp update_statuses(%{"data" => responses} = _params, org_id) do
    responses
    |> Enum.each(fn response ->
      case response do
        %{"options" => _options} ->
          update_poll_response(response, org_id)

        %{"reaction" => _reaction} ->
          handle_reactions(response, org_id)

        %{"ackType" => ack_type} ->
          do_update_status(response, ack_type, org_id)
      end
    end)
  end

  defp update_statuses(_payload, _org_id) do
    # catch-all for payloads we dont want to handle
    nil
  end

  # Updates the provider message statuses based on provider message id
  @spec do_update_status(map(), String.t(), non_neg_integer()) :: any()
  defp do_update_status(params, ack_type, org_id) do
    status = Map.get(@message_event_type, ack_type)
    bsp_message_id = Map.get(params, "msgId")
    Communications.GroupMessage.update_bsp_status(bsp_message_id, status, org_id)
  end

  @spec do_update_error_status(map(), non_neg_integer()) :: any()
  defp do_update_error_status(params, org_id) do
    bsp_message_id = Map.get(params["data"], "id")
    Communications.GroupMessage.update_bsp_error_status(bsp_message_id, params, org_id)
  end

  @spec handle_reactions(map(), non_neg_integer()) :: any()
  defp handle_reactions(params, org_id) do
    params
    |> Communications.GroupMessage.receive_reaction_msg(org_id)
  end

  @spec update_poll_response(map(), non_neg_integer()) :: any()
  defp update_poll_response(response, org_id) do
    bsp_message_id = Map.get(response, "msgId")

    poll_content = %{
      "text" => response["text"],
      "options" => response["options"]
    }

    Communications.GroupMessage.update_poll_content(bsp_message_id, poll_content, org_id)
  end
end
