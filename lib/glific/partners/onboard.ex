defmodule Glific.Partners.Onboard do
  @moduledoc """
  For now, we will build this on top of organization table, and have a group of helper functions
  here to manage global operations across all organizations.
  At some later point, we might decide to have a separate onboarding table and managment structure
  """
  import GlificWeb.Gettext
  import Ecto.Query

  alias Glific.{
    Contacts,
    Partners,
    Partners.Organization,
    Providers.Gupshup.ApiClient,
    Providers.GupshupContacts,
    Repo
  }

  alias Pow.Ecto.Schema.Changeset

  @doc """
  Setup all the tables and necessary values to onboard an organization
  """
  @spec setup(map()) :: map()
  def setup(params) do
    %{is_valid: true, messages: []}
    |> validate(params)
    |> setup(params)
  end

  @spec setup(map(), map()) :: map()
  defp setup(result, params) do
    result
    # first create the organization
    |> organization(params)
    # then create the contact and associate contact with organization
    |> contact(params)
    # create the credentials
    |> credentials(params)
  end

  @spec organization(map(), map()) :: map()
  defp organization(%{is_valid: false} = result, _params), do: result

  defp organization(result, params) do
    attrs = %{
      name: params["name"],
      shortcode: params["shortcode"],
      email: params["email"],
      bsp_id: 1,
      default_language_id: 1,
      active_language_ids: [1],
      timezone: "Asia/Kolkata",
      is_active: false,
      is_approved: false
    }

    case Partners.create_organization(attrs) do
      {:ok, organization} ->
        Repo.put_organization_id(organization.id)
        Map.put(result, :organization, organization)

      {:error, errors} ->
        result
        |> Map.put(:is_valid, false)
        |> Map.update!(:messages, fn msgs -> [inspect(errors) | msgs] end)
    end
  end

  @spec contact(map(), map()) :: map()
  defp contact(%{is_valid: false} = result, _params), do: result

  defp contact(result, params) do
    attrs = %{
      phone: params["phone"],
      language_id: result.organization.default_language_id,
      organization_id: result.organization.id
    }

    case Contacts.create_contact(attrs) do
      {:ok, contact} ->
        {:ok, organization} =
          Partners.update_organization(
            result.organization,
            %{contact_id: contact.id}
          )

        result
        |> Map.put(:organization, organization)
        |> Map.put(:contact, contact)

      {:error, errors} ->
        result
        |> Map.put(:is_valid, false)
        |> Map.update!(:messages, fn msgs -> [inspect(errors) | msgs] end)
    end
  end

  @spec credentials(map(), map()) :: map()
  defp credentials(%{is_valid: false} = result, _params), do: result

  defp credentials(result, params) do
    attrs = %{
      shortcode: "gupshup",
      keys: %{
        "url" => "https://gupshup.io/",
        "worker" => "Glific.Providers.Gupshup.Worker",
        "handler" => "Glific.Providers.Gupshup.Message",
        "bsp_limit" => 40,
        "api_end_point" => "https://api.gupshup.io/sm/api/v1"
      },
      secrets: %{
        "api_key" => params["api_key"],
        "app_name" => params["app_name"]
      },
      organization_id: result.organization.id
    }

    case Partners.create_credential(attrs) do
      {:ok, credential} ->
        Map.put(result, :credential, credential)

      {:error, errors} ->
        result
        |> Map.put(:is_valid, false)
        |> Map.update!(:messages, fn msgs -> [inspect(errors) | msgs] end)
    end
  end

  # validate all the input elements
  @spec validate(map(), map()) :: map()
  defp validate(result, params) do
    result
    |> validate_bsp_keys(params)
    |> validate_shortcode(params["shortcode"])
    |> validate_email(params["email"])
    |> validate_phone(params["phone"])
  end

  @spec error(String.t(), map()) :: map()
  defp error(message, result) do
    result
    |> Map.put(:is_valid, false)
    |> Map.update!(:messages, fn msgs -> [message | msgs] end)
  end

  # return if a string is nil or empty
  @spec empty(String.t() | nil) :: boolean
  defp empty(str), do: is_nil(str) || str == ""

  # Validate the APIKey and AppName entered by the organization. We will use the gupshup
  # opt-in url which requires both and ensure that it returns success to validate these two
  # parameters
  @spec validate_bsp_keys(map(), map()) :: map()
  defp validate_bsp_keys(result, params) do
    api_key = params["api_key"]
    app_name = params["app_name"]

    if empty(api_key) || empty(app_name) do
      dgettext("error", "API Key or App Name is empty")
      |> error(result)
    else
      validate_bsp_keys(result, api_key, app_name)
    end
  end

  @spec validate_bsp_keys(map(), String.t(), String.t()) :: map()
  defp validate_bsp_keys(result, api_key, app_name) do
    response =
      ApiClient.users_get(api_key, app_name)
      |> GupshupContacts.validate_opted_in_contacts()

    case response do
      {:ok, _users} -> result

      {:error, message} -> error(message, result)
    end
  end

  # Ensure this shortcode is currently not being used
  @spec validate_shortcode(map(), String.t()) :: map()
  defp validate_shortcode(result, nil) do
    dgettext("error", "Shortcode cannot be empty") |> error(result)
  end

  defp validate_shortcode(result, shortcode) do
    o =
      Organization
      |> where([o], o.shortcode == ^shortcode)
      |> select([o], o.id)
      |> Repo.all()

    if o == [] do
      result
    else
      dgettext("error", "Shortcode has already been taken")
      |> error(result)
    end
  end

  @spec validate_email(map(), String.t()) :: map()
  defp validate_email(result, email) do
    case Changeset.validate_email(email) do
      :ok ->
        result

      _ ->
        dgettext("error", "Email is not valid.")
        |> error(result)
    end
  end

  @spec validate_phone(map(), String.t()) :: map()
  defp validate_phone(result, phone) do
    case ExPhoneNumber.parse(phone, "IN") do
      {:ok, _phone} ->
        result

      _ ->
        dgettext("error", "Phone is not valid.")
        |> error(result)
    end
  end
end
