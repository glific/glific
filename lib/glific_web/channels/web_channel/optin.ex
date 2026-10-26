defmodule GlificWeb.WebChannel.Optin do
  @moduledoc """
  Records the consent a web sign-in carries. The user is already signed in by then, so a failure is
  logged and never refuses the sign-in.
  """

  alias Glific.{Contacts, SafeLog}

  @doc """
  Opts the web `identifier` in on the web channel via `method`, logging instead of failing.
  """
  @spec record(String.t(), non_neg_integer(), String.t()) :: :ok
  def record(identifier, organization_id, method) do
    case Contacts.contact_opted_in(:web, identifier, %{organization_id: organization_id},
           method: method
         ) do
      {:ok, _contact} ->
        :ok

      {:error, reason} ->
        Glific.log_error(
          "Web channel opt-in via #{method} not recorded: #{SafeLog.safe_inspect(reason)}"
        )

        :ok
    end
  end
end
