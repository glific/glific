defmodule Glific.Partners.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """
  import GlificWeb.Gettext
  import Ecto.Query

  alias Glific.{
    Partners.Organization,
    Providers.GupshupContacts,
    Providers.Gupshup.ApiClient,
    Repo
  }

  # return if a string is nil or empty
  @spec empty(String.t() | nil) :: boolean
  defp empty(str), do: is_nil(str) || str == ""

  @doc """
  Validate the APIKey and AppName entered by the organization. We will use the gupshup
  opt-in url which requires both and ensure that it returns success to validate these two
  parameters
  """
  @spec validate_bsp_keys(map()) :: map()
  def validate_bsp_keys(params) do
    api_key = params["api_key"]
    app_name = params["app_name"]

    if empty(api_key) || empty(app_name),
      do: %{
        is_valid: false,
        message: dgettext("error", "API Key or App Name is empty")
      },
      else: validate_bsp_keys(api_key, app_name)
  end

  @spec validate_bsp_keys(String.t(), String.t()) :: map()
  defp validate_bsp_keys(api_key, app_name) do
    result =
      ApiClient.users_get(api_key, app_name)
      |> GupshupContacts.validate_opted_in_contacts()

    case result do
      {:ok, _users} ->
        %{is_valid: true}

      {:error, message} ->
        %{
          is_valid: false,
          message: message
        }
    end
  end

  @spec validate_shortcode(String.t()) :: map()
  def validate_shortcode(shortcode) do
    o =
      Organization
      |> where([o], o.shortcode == ^shortcode)
      |> select([o], o.id)
      |> Repo.all()

    if o == [],
      do: %{is_valid: true},
      else: %{
        is_valid: false,
        message: dgettext("error", "Shortcode has already been taken")
      }
  end
end
