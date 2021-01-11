defmodule Glific.Messages.MessageVariables do
  @moduledoc """
  Create maps for substitutions in message body
  These maps of available variables will be required by frontend team
  """

  @doc """
  Get map of global variables
  """
  @spec get_global_field_map :: map() | :error
  def get_global_field_map do
    case Application.fetch_env(:glific, :app_base_url) do
      {:ok, base_url} ->
        %{
          registration: %{
            url: base_url <> "registration"
          }
        }

        # in case base url does not exiss, for now we return an empty
        # map
      _ -> %{}
    end
  end
end
