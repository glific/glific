defmodule Glific.AI.Credentials do
  @moduledoc """
  Resolves the API key an agent skill's model call authenticates with: the requesting
  organisation's own credential first, a platform-wide key otherwise.

  Per-organisation credentials, cached on `organization.services` (`Glific.Partners.organization/1`,
  keyed by provider shortcode — the same shape `Glific.OpenAI.ChatGPT.credentials/1` reads),
  take precedence so API cost is attributable to the organisation that incurred it, and so a
  runaway loop in one tenant's agent cannot exhaust — or rate-limit — every other tenant's key.
  Only an *active* credential counts — see `Glific.Partners.set_credentials/1`, which excludes
  `is_active: false` rows from `organization.services` entirely.

  Never put the resolved key into an Oban job's `args`: jobs are stored as JSON rows and surface
  in AppSignal job payloads, so a key placed there is a credential leak waiting to happen. Call
  `fetch/2` fresh inside the process that makes the model call.
  """

  alias Glific.Partners
  alias Glific.Partners.Organization
  alias Glific.SafeLog

  @typedoc "A provider from `Glific.AI.Codec`'s closed provider whitelist."
  @type provider :: :anthropic | :google | :openai | :openrouter

  @doc """
  Resolves the API key for `provider` inside `organization_id`.
  """
  @spec fetch(non_neg_integer(), provider()) :: {:ok, String.t()} | {:error, String.t()}
  def fetch(organization_id, provider) when is_atom(provider) do
    organization_id
    |> Partners.organization()
    |> org_key(provider)
    |> case do
      key when is_binary(key) and key != "" -> {:ok, key}
      _no_org_credential -> platform_key(provider)
    end
  end

  @spec org_key(Organization.t(), provider()) :: String.t() | nil
  defp org_key(%Organization{services: services}, provider) do
    case Map.get(services, Atom.to_string(provider)) do
      %{secrets: %{"api_key" => api_key}} -> api_key
      _no_credential -> nil
    end
  end

  @spec platform_key(provider()) :: {:ok, String.t()} | {:error, String.t()}
  defp platform_key(:anthropic), do: wrap(Glific.get_anthropic_api_key())
  defp platform_key(:openai), do: wrap(Glific.get_open_ai_key())
  defp platform_key(:google), do: wrap(Glific.get_google_api_key())

  defp platform_key(provider),
    do:
      {:error, "no platform credential configured for provider #{SafeLog.safe_inspect(provider)}"}

  @spec wrap(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  defp wrap(key) when is_binary(key) and key != "", do: {:ok, key}
  defp wrap(_missing), do: {:error, "no API key configured"}
end
