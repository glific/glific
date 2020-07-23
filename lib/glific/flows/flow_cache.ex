defmodule Glific.Flows.FlowCache do
  @moduledoc """
  The flow object which encapsulates the complete flow as emitted by
  by `https://github.com/nyaruka/floweditor`
  """

  @doc """
  Store all the flows in cachex :flows_cache. At some point, we will just use this dynamically
  """
  @spec set_flow(Ecto.UUID.t()) :: any()
  def set_flow(args) do
    flow = Glific.Flows.Flow.get_loaded_flow(args)
    {:ok, true} = Cachex.put(:flows_cache, flow.uuid, flow)
    {:ok, true} = Cachex.put(:flows_cache, flow.shortcode, flow)
    flow
  end

  @doc """
    Get the flow from cache based on shortcode or
  """
  @spec get_flow(Ecto.UUID.t()) :: any()
  def get_flow(uuid) do
    get_flow(%{uuid: uuid})
  end

  @spec get_flow(map()) :: any()
  def get_flow(args) do
    # %{ label => key} = args

    # with {:ok, true} <- Cachex.exists?(:flows_cache, key),
    #       {:ok, flow} <- Cachex.get(:flows_cache, key) do
    # else
    #   _ -> set_flow(%{label => key})
    # end
  end


  @spec reload_flow(map()) :: Glific.Flows.Flow.t()
  def reload_flow(args \\ %{}) do
      flow = Glific.Flows.Flow.get_loaded_flow(args)
      Cachex.update(:my_cache, flow.uuid, flow)
      flow
  end

  @spec remove_flow(Ecto.UUID.t()) :: boolean()
  def remove_flow(uuid) do
   { :ok, true } =  Cachex.del(:my_cache, uuid)
   true
  end

end
