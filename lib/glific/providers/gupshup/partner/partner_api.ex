defmodule Glific.Providers.Gupshup.PartnerAPI do
  @moduledoc """
  A module to handle fetching tier related information like quality rating and app rating using partner API
  """

  alias Glific.{
    Caches,
    Partners,
    Partners.Saas
  }

  use Tesla
  require Logger

  alias Plug.Conn.Query
  alias Tesla.Multipart

  plug(Tesla.Middleware.FormUrlencoded,
    encode: &Query.encode/1
  )

  @partner_url "https://partner.gupshup.io/partner/account"
  @app_url "https://partner.gupshup.io/partner/app/"

  @modes ["ENQUEUED", "FAILED", "READ", "SENT", "DELIVERED", "OTHERS", "DELETE", "MESSAGE"]

  @doc """
  Fetch app details by org id, will link the app if not linked
  """
  @spec fetch_app_details(non_neg_integer()) :: map() | String.t()
  def fetch_app_details(org_id) do
    link_gupshup_app(org_id)
    |> case do
      {:ok, res} ->
        res["partnerApps"]

      {:error, error} ->
        error = "#{inspect(error)}"

        if String.contains?(error, "Re-linking"),
          do: fetch_gupshup_app_details(org_id),
          else: error
    end
  end

  @doc """
  Fetches Partner token and App Access token to get tier information
  for an organization with input app id
  """
  @spec get_quality_rating(non_neg_integer()) :: {:error, any} | {:ok, map()}
  def get_quality_rating(org_id) do
    (app_url!(org_id) <> "/ratings")
    |> get_request(org_id: org_id)
    |> case do
      {:ok, res} ->
        {:ok,
         %{
           current_limit: res["currentLimit"],
           event: res["event"],
           event_time: res["eventTime"],
           previous_limit: res["oldLimit"]
         }}

      error ->
        {:error, "Error while getting the ratings. #{inspect(error)}"}
    end
  end

  @doc """
   Get Gupshup media handle id based on giving org id and the URL. media_name is used as a label for the resource
  """
  @spec get_media_handle_id(non_neg_integer, binary, String.t()) :: String.t() | term()
  def get_media_handle_id(org_id, url, media_name) do
    with {:ok, path} <- get_resource_local_path(url, media_name) do
      data =
        Multipart.new()
        |> Multipart.add_file(path, name: "file")
        |> Multipart.add_field("file_type", MIME.from_path(url))

      (app_url!(org_id) <> "/upload/media")
      |> post_request(data,
        org_id: org_id
      )
      |> case do
        {:ok, %{"status" => "success", "handleId" => %{"message" => handle_id}} = _res} ->
          handle_id

        {:error, error} ->
          raise(error)
      end
    end
  end

  @doc """
    App Link Using API key (works to get app ID the first time while creating)
  """
  @spec link_gupshup_app(non_neg_integer()) :: tuple()
  def link_gupshup_app(org_id) do
    organization = Partners.organization(org_id)
    gupshup_secrets = organization.services["bsp"].secrets

    post_request(
      @partner_url <> "/api/appLink",
      %{
        apiKey: gupshup_secrets["api_key"],
        appName: gupshup_secrets["app_name"]
      },
      token_type: :partner_token
    )
  end

  @wallet_name "4000202160_wallet"
  @doc """
    Transfer balance from ISV partner to app
  """
  @spec recharge_partner(String.t(), float()) :: tuple()
  def recharge_partner(customer_id, amount) do
    post_request(
      @partner_url <> "/api/wallet/balance/transfer",
      %{
        walletName: @wallet_name,
        customerId: customer_id,
        amount: amount
      },
      token_type: :partner_token
    )
  end

  @doc """
  Fetch Gupshup app details by orgId or Gupshup app name
  """
  @spec fetch_gupshup_app_details(non_neg_integer() | String.t()) :: map() | String.t()
  def fetch_gupshup_app_details(org_id) when is_number(org_id) do
    organization = Partners.organization(org_id)
    gupshup_secrets = organization.services["bsp"].secrets
    gupshup_app_name = gupshup_secrets["app_name"]
    do_fetch_app_details(gupshup_app_name)
  end

  def fetch_gupshup_app_details(app_name) when is_binary(app_name) do
    do_fetch_app_details(app_name)
  end

  @doc """
  Enable template messaging for an app.
  """
  @spec enable_template_messaging(non_neg_integer()) :: tuple()
  def enable_template_messaging(org_id) do
    url = app_url!(org_id) <> "/appPreference"
    data = %{"isHSMEnabled" => "true"}
    put_request(url, data, org_id: org_id)
  end

  @doc """
  Remove hsm template from the WABA.
  """
  @spec delete_hsm_template(non_neg_integer, binary) :: tuple()
  def delete_hsm_template(org_id, element_name) do
    (app_url!(org_id) <> "/template/" <> element_name)
    |> delete_request(org_id: org_id)
    |> case do
      {:ok, %{"status" => "success"} = res} ->
        {:ok, res}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Edit pre approved template
  """
  @spec edit_approved_template(non_neg_integer(), String.t(), map) :: tuple()
  def edit_approved_template(org_id, bsp_id, params) do
    (app_url!(org_id) <> "/templates/" <> bsp_id)
    |> put_request(params, org_id: org_id)
  end

  @doc """
  Sending HSM template to contact
  """
  @spec send_template(non_neg_integer(), map()) :: Tesla.Env.result() | {:error, String.t()}
  def send_template(org_id, payload) do
    req_headers = headers(:app_token, org_id: org_id)

    (app_url!(org_id) <> "/template/msg")
    |> post(payload, headers: req_headers)
  end

  @doc """
  Remove hsm template from the WABA.
  """
  @spec apply_for_template(non_neg_integer(), map) :: tuple()
  def apply_for_template(org_id, payload) do
    payload = Map.put(payload, :appId, app_id!(org_id))

    (app_url!(org_id) <> "/templates")
    |> post_request(payload,
      org_id: org_id
    )
    |> case do
      {:ok, response} ->
        {:ok, response}

      {:error, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        decoded_body = Jason.decode!(body)
        {:error, decoded_body["message"]}

      unmatched_response ->
        Logger.error("#{inspect(unmatched_response)}")
        {:error, "Something went wrong, not able to submit the template for approval."}
    end
  end

  @doc """
  Setting Business Profile Details.
  Following parameters can be updated in the given form:
  %{
  addLine1: "123",
  addLine2: "panvel",
  city: "mumbai",
  state: "maharashtra",
  pinCode: 123,
  country: "india",
  vertical: "saloon",
  website1: "123.com",
  website2: "123.com",
  desc: "see desc",
  profileEmail: "123@gmail.com"}
  """
  @spec set_business_profile(integer(), map()) :: tuple()
  def set_business_profile(org_id, params \\ %{}) do
    url = app_url!(org_id) <> "/business/profile"

    body_params =
      Enum.reduce(params, %{}, fn {key, value}, acc ->
        if value == nil, do: acc, else: Map.put(acc, key, value)
      end)

    put_request(url, body_params, org_id: org_id)
  end

  @doc """
  Downloads the resource from the given url and returns the local path
  """
  @spec get_resource_local_path(String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_resource_local_path(resource_url, media_name) do
    case Tesla.get(resource_url) do
      {:ok, %Tesla.Env{body: body}} ->
        file_name = get_filename_from_resource_url(resource_url, media_name)
        :ok = File.write!(file_name, body)
        {:ok, file_name}

      {:error, err} ->
        Logger.error("Error downloading file due to #{inspect(err)}")
        {:error, "#{inspect(err)}"}
    end
  end

  @doc """
  Deletes the file, that has been downloaded locally by the `get_resource_local_path/2`
  """
  @spec delete_local_resource(nil | String.t(), String.t()) :: :ok | {:error, atom()}
  def delete_local_resource(nil, _media_name), do: :ok

  def delete_local_resource(resource_url, media_name) do
    resource_url
    |> get_filename_from_resource_url(media_name)
    |> File.rm()
  end

  @doc """
  gets daily app usage b/w two dates
  """
  @spec get_app_usage(non_neg_integer(), String.t(), String.t()) ::
          {:error, String.t()} | {:ok, list(map())}
  def get_app_usage(org_id, from_date, to_date) do
    url = app_url!(org_id) <> "/usage?from=" <> from_date <> "&to=" <> to_date

    case get_request(url, org_id: org_id) do
      {:ok, %{"partnerAppUsageList" => result}} -> {:ok, result}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Gets the remaining Gupshup balance
  """
  @spec get_balance(non_neg_integer()) :: {:ok, map()} | {:error, String.t()}
  def get_balance(org_id) do
    with {:ok, app_url} <- app_url(org_id),
         {:ok, resp} <-
           get_request(
             app_url <> "/wallet/balance",
             org_id: org_id
           ) do
      {:ok, %{"balance" => resp["walletResponse"]["currentBalance"]}}
    end
  end

  @doc """
  Fetch HSM templates using partner token (Gupshup partner API)
  """
  @spec get_templates(non_neg_integer()) :: {:ok, any()} | {:error, String.t()}
  def get_templates(org_id) do
    with {:ok, %{partner_app_token: token}} <- get_partner_app_token(org_id) do
      url = app_url!(org_id) <> "/templates"
      headers = [{"Authorization", token}]
      get(url, headers: headers)
    end
  end

  @global_organization_id 0
  @spec get_partner_token :: {:ok, map()} | {:error, any}
  defp get_partner_token do
    # disabling the cache refresh because by default whenever
    # we fetch the info from cache it refreshes the TTL
    {:ok, partner_token} =
      Caches.get(@global_organization_id, "partner_token", refresh_cache: false)

    if partner_token,
      do: {:ok, %{partner_token: partner_token}},
      else: fetch_partner_token()
  end

  @spec fetch_partner_token :: {:ok, map()} | {:error, any}
  defp fetch_partner_token do
    url = @partner_url <> "/login"
    credentials = Saas.isv_credentials()

    request_params = %{"email" => credentials["email"], "password" => credentials["password"]}

    post(url, request_params, headers: [])
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        res = Jason.decode!(body)

        {:ok, token} =
          Caches.set(@global_organization_id, "partner_token", res["token"],
            ttl: :timer.hours(22)
          )

        {:ok, %{partner_token: token}}

      {_status, response} ->
        {:error, "Could not fetch the partner token #{inspect(response)}"}
    end
  end

  @spec get_partner_app_token(non_neg_integer) ::
          {:error, String.t()} | {:ok, %{partner_app_token: any}}
  defp get_partner_app_token(org_id) do
    {:ok, partner_app_token} = Caches.get(org_id, "partner_app_token", refresh_cache: false)

    if partner_app_token,
      do: {:ok, %{partner_app_token: partner_app_token}},
      else: fetch_partner_app_token(org_id)
  end

  @spec fetch_partner_app_token(non_neg_integer) ::
          {:error, String.t()} | {:ok, %{partner_app_token: any}}
  defp fetch_partner_app_token(org_id) do
    url = app_url!(org_id) <> "/token"

    get_request(url, token_type: :partner_token)
    |> case do
      {:ok, res} ->
        app_token = get_in(res, ["token", "token"])
        Caches.set(org_id, "partner_app_token", app_token, ttl: :timer.hours(22))
        {:ok, %{partner_app_token: app_token}}

      {:error, error} ->
        {:error, "Could not fetch the partner app token #{inspect(error)}"}
    end
  end

  @spec headers(atom(), Keyword.t()) :: list()
  defp headers(:app_token, opts) do
    org_id = Keyword.get(opts, :org_id)

    case get_partner_app_token(org_id) do
      {:ok, %{partner_app_token: partner_app_token}} ->
        [{"token", partner_app_token}, {"Authorization", partner_app_token}]

      error ->
        # in case we cant find the app token, log an error, but return a empty list so we proceed
        Logger.error("Could not fetch partner app token: #{inspect(error)}")
        []
    end
  end

  defp headers(:partner_token, _opts) do
    get_partner_token()
    |> case do
      {:ok, %{partner_token: partner_token}} ->
        [
          {"token", partner_token},
          {"Authorization", partner_token}
        ]

      _ ->
        []
    end
  end

  @spec post_request(String.t(), map(), Keyword.t()) :: tuple()
  defp post_request(url, data, opts) do
    req_headers =
      headers(Keyword.get(opts, :token_type, :app_token), opts)

    post(url, data, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      {:ok, resp} ->
        {:error, resp}

      err ->
        {:error, err}
    end
  end

  @spec put_request(String.t(), map(), Keyword.t()) :: tuple()
  defp put_request(url, data, opts) do
    req_headers = headers(Keyword.get(opts, :token_type, :app_token), opts)

    put(url, data, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      err ->
        {:error, "#{inspect(err)}"}
    end
  end

  @spec get_request(String.t(), Keyword.t()) :: tuple()
  defp get_request(url, opts) do
    req_headers =
      headers(Keyword.get(opts, :token_type, :app_token), opts)

    get(url, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      err ->
        {:error, "#{inspect(err)}"}
    end
  end

  @spec delete_request(String.t(), Keyword.t()) :: tuple()
  defp delete_request(url, opts) do
    req_headers = headers(Keyword.get(opts, :token_type, :app_token), opts)

    delete(url, headers: req_headers)
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Jason.decode!(body)}

      err ->
        {:error, "#{inspect(err)}"}
    end
  end

  @doc """
    Fetch App ID
  """
  @spec app_id(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  def app_id(org_id) do
    organization = Partners.organization(org_id)
    bsp_service = organization.services["bsp"]

    cond do
      is_nil(bsp_service) ->
        {:error, "Gupshup is not active"}

      bsp_service.secrets["app_id"] in [nil, ""] ->
        {:error, "App Id not found"}

      true ->
        {:ok, bsp_service.secrets["app_id"]}
    end
  end

  @doc """
  Creates a webhook in gupshup

  - org_id - Unique organization Id
  - callback_url - Webhook callback url, defaults to auto generated url wrto org shortcode
  - modes - Different modes we want to listen to, check `@modes` for defaults
  - version - Payload format, by default its v2 (gupshup format)
  """
  @spec set_subscription(non_neg_integer(), String.t() | nil, list(String.t()), non_neg_integer()) ::
          tuple()
  def set_subscription(org_id, callback_url \\ nil, modes \\ [], version \\ 2)
      when is_list(modes) do
    url = app_url!(org_id) <> "/subscription"
    organization = Partners.organization(org_id)

    # sometimes callback url can be ngrok or other test urls, in that
    # case we can pass in the function
    callback_url =
      if is_nil(callback_url) do
        "https://api.#{organization.shortcode}.glific.com/gupshup"
      else
        callback_url
      end

    # modes can be passed in params,
    # if we want to add a newly introduced event other than
    # the defaults
    modes = (@modes ++ Enum.map(modes, &String.upcase/1)) |> Enum.uniq() |> Enum.join(",")

    data = %{
      "modes" => modes,
      "tag" => "webhook_#{organization.shortcode}",
      "url" => callback_url,
      "version" => version
    }

    post_request(url, data, org_id: org_id)
  end

  @spec app_id!(non_neg_integer()) :: String.t()
  defp app_id!(org_id) do
    {:ok, app_id} = app_id(org_id)
    app_id
  end

  @spec app_url!(non_neg_integer()) :: String.t()
  defp app_url!(org_id),
    do: @app_url <> app_id!(org_id)

  @spec app_url(non_neg_integer()) :: {:ok, String.t()} | {:error, String.t()}
  defp app_url(org_id) do
    with {:ok, app_id} <- app_id(org_id) do
      {:ok, @app_url <> app_id}
    end
  end

  @spec get_filename_from_resource_url(String.t(), String.t()) :: String.t()
  defp get_filename_from_resource_url(resource_url, media_name) do
    file_format =
      MIME.from_path(resource_url)
      |> String.split("/")
      |> List.last()

    "template-asset-#{media_name}.#{file_format}"
  end

  @spec do_fetch_app_details(String.t()) :: map() | String.t()
  defp do_fetch_app_details(app_name) do
    with {:ok, %{"partnerAppsList" => list}} <-
           get_request(@partner_url <> "/api/partnerApps", token_type: :partner_token),
         [app | _] <- Enum.filter(list, fn app -> app["name"] == app_name end) do
      app
    else
      {:error, error} ->
        error

      _ ->
        "Invalid Gupshup App"
    end
  end
end
