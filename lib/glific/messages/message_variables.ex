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
    with {:ok, base_url} <- Application.fetch_env(:glific, :app_bases_url) do
      %{
        registration: %{
          url: base_url <> "registration"
        }
      }
    end
  end
end
