defmodule Glific do
  import Ecto.Changeset

  @moduledoc """
  Glific keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.

  For now we'll keep some commonly used functions here, until we need
  a new file
  """
  @captcha_verify_url "https://www.google.com/recaptcha/api/siteverify"
  @captcha_score_threshold 0.5
  @session_window_time 24

  require Logger

  alias Glific.{
    Partners,
    Repo
  }

  alias Tesla.Multipart

  @doc """
  Default session window time in Glific
  """
  @spec session_window_time() :: integer()
  def session_window_time, do: @session_window_time

  @doc """
  Wrapper to return :ok/:error when parsing strings to potential integers
  """
  @spec parse_maybe_integer(String.t() | integer) :: {:ok, integer} | {:ok, nil} | :error
  def parse_maybe_integer(value) when is_integer(value),
    do: {:ok, value}

  def parse_maybe_integer(nil),
    do: {:ok, nil}

  def parse_maybe_integer(value) do
    case Integer.parse(value) do
      {n, ""} -> {:ok, n}
      {_num, _rest} -> :error
      :error -> :error
    end
  end

  @doc """
  parse and integer and die if parse fails
  """
  @spec parse_maybe_integer!(String.t() | integer) :: integer
  def parse_maybe_integer!(value) do
    {:ok, value} = parse_maybe_integer(value)
    value
  end

  @doc """
  Wrapper to return :ok/:error when parsing strings to potential integers
  """
  @spec parse_maybe_number(String.t() | integer) :: {:ok, integer} | {:ok, nil} | :error
  def parse_maybe_number(nil),
    do: {:ok, nil}

  def parse_maybe_number(value) when is_integer(value),
    do: {:ok, value}

  def parse_maybe_number(value) when is_float(value),
    do: {:ok, value}

  def parse_maybe_number(value) do
    case Integer.parse(value) do
      :error ->
        :error

      {n, ""} ->
        {:ok, n}

      _ ->
        Float.parse(value)
        |> case do
          {n, ""} -> {:ok, n}
          _ -> :error
        end
    end
  end

  @doc """
  Validates inputted shortcode, if shortcode is invalid it returns message that the shortcode is invalid
  along with the valid shortcode.
  """
  @spec(
    validate_shortcode(Ecto.Changeset.t()) :: Ecto.Changeset.t() | Ecto.Changeset.t(),
    atom(),
    String.t()
  )
  def validate_shortcode(%Ecto.Changeset{} = changeset) do
    shortcode = Map.get(changeset.changes, :shortcode)
    valid_shortcode = string_clean(shortcode)

    if valid_shortcode == shortcode,
      do: changeset,
      else:
        add_error(
          changeset,
          :shortcode,
          "Invalid shortcode, valid shortcode will be  #{valid_shortcode}"
        )
  end

  @doc """
  Lets get rid of all non valid characters. We are assuming any language and hence using unicode syntax
  and not restricting ourselves to alphanumeric
  """
  @spec string_clean(String.t() | nil) :: String.t() | nil
  def string_clean(str) when is_nil(str) or str == "", do: str

  def string_clean(str),
    do:
      str
      |> String.replace(~r/[\p{P}\p{S}\p{Z}\p{C}]+/u, "")
      |> String.downcase()
      |> String.trim()

  @doc """
  convert string to snake case
  """
  @spec string_snake_case(String.t() | nil) :: String.t() | nil
  def string_snake_case(str) when is_nil(str) or str == "", do: str

  def string_snake_case(str),
    do:
      str
      |> String.replace(~r/\s+/, "_")
      |> String.downcase()

  @doc """
  See if the current time is within the past time units
  """
  @spec in_past_time(DateTime.t(), atom(), integer) :: boolean
  def in_past_time(time, units \\ :hours, back \\ 24),
    do: Timex.diff(DateTime.utc_now(), time, units) < back

  @doc """
  Return a time object where you go back x units. We introduce the notion
  of hour and minute
  """
  @spec go_back_time(integer, DateTime.t(), atom()) :: DateTime.t()
  def go_back_time(go_back, time \\ DateTime.utc_now(), unit \\ :hour) do
    # convert hours to second
    {unit, go_back} =
      case unit do
        :hour -> {:second, go_back * 60 * 60}
        :minute -> {:second, go_back * 60}
        _ -> {unit, go_back}
      end

    DateTime.add(time, -1 * go_back, unit)
  end

  @doc """
  Convert map string keys to :atom keys
  """
  @spec atomize_keys(any) :: any
  def atomize_keys(nil), do: nil

  # Structs don't do enumerable and anyway the keys are already
  # atoms
  def atomize_keys(map) when is_struct(map),
    do: map

  def atomize_keys([head | rest] = list) when is_list(list),
    do: [atomize_keys(head) | atomize_keys(rest)]

  def atomize_keys(map) when is_map(map) do
    for {key, val} <- map,
        into: %{},
        do: {Glific.safe_string_to_atom(key), atomize_keys(val)}
  end

  def atomize_keys(value), do: value

  @doc """
  easy way for glific developers to get a stacktrace when debugging
  """
  @spec stacktrace :: String.t()
  def stacktrace do
    {_, stacktrace} = Process.info(self(), :current_stacktrace)
    inspect(stacktrace)
  end

  @not_allowed ["Repo.", "IO.", "File.", "Code."]

  @doc """
  Really simple function to ensure folks do not add Repo and/or IO calls
  to an EEx snippet. This is an extremely short term fix to avoid shooting
  ourselves in the foot, but we should move to lua for flows scripting in the
  near future

  Note that folks can potentially find other ways to access the same modules, so
  this by no means should be considered remotely secure
  """
  @spec suspicious_code(String.t()) :: boolean()
  def suspicious_code(code),
    do: String.contains?(code, @not_allowed)

  @doc """
  execute string in eex
  """
  @spec execute_eex(String.t()) :: String.t()
  def execute_eex(content) do
    if suspicious_code(content) do
      Logger.error("EEx suspicious code: #{content}")
      "Suspicious Code. Please change your code. #{content}"
    else
      content
      |> EEx.eval_string()
      |> String.trim()
    end
  rescue
    EEx.SyntaxError ->
      Logger.error("EEx threw a SyntaxError: #{content}")
      "Invalid Code"

    _ ->
      Logger.error("EEx threw a Error: #{content}")
      "Invalid Code"
  end

  @doc """
  Compute the signature at a specific time for the body
  """
  @spec signature(non_neg_integer, String.t(), non_neg_integer) :: String.t()
  def signature(organization_id, body, timestamp) do
    secret = Partners.organization(organization_id).signature_phrase

    # 2731 - create a default if does not exist
    secret =
      if secret in ["", nil],
        do: "This is a dummy secret",
        else: secret

    signed_payload = "#{timestamp}.#{body}"
    hmac = :crypto.mac(:hmac, :sha256, secret, signed_payload)
    Base.encode16(hmac, case: :lower)
  end

  @doc """
  You shouldn’t really use String.to_atom/1 on user-supplied data.
  The BEAM has a limit on how many different atoms you can have and they’re not garbage collected!
  With data coming from outside the system, stick to strings or use String.to_existing_atom/1 instead!
  So this is a generic function which will convert the string to atom and throws an error in case of invalid key
  """

  @spec safe_string_to_atom(String.t() | atom(), atom()) :: atom()
  def safe_string_to_atom(value, default \\ :invalid_atom)

  def safe_string_to_atom(value, _default) when is_atom(value), do: value

  def safe_string_to_atom(value, default) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      error = "#{value} can not be converted to atom"
      Appsignal.send_error(:error, error, __STACKTRACE__)
      default
  end

  @doc """
  Delete multiple items from the map
  """
  @spec delete_multiple(map(), list()) :: map()
  def delete_multiple(map, list) do
    list
    |> Enum.reduce(
      map,
      fn l, acc -> Map.delete(acc, l) end
    )
  end

  @doc """
  Given a string separated by spaces, commas, or semi-colons, create a set of individual
  elements in the string
  """
  @spec make_set(String.t(), list()) :: MapSet.t()
  def make_set(str, separators \\ [",", ";"]) do
    str
    # string downcase for making it case-insensitive
    |> String.downcase()
    # First ALWAYS split by white space
    |> String.split()
    # then split by separators
    |> Enum.flat_map(fn x -> String.split(x, separators, trim: true) end)
    # finally create a mapset for easy fast checks
    |> MapSet.new()
  end

  @doc """
  Intermediary function to update the input params with organization id
  as operation is performed by glific_admin for other organizations
  """
  @spec substitute_organization_id(map(), any, atom()) :: map()
  def substitute_organization_id(params, value, key) when is_integer(value),
    do: substitute_organization_id(params, "#{value}", key)

  def substitute_organization_id(params, value, key) do
    value
    |> String.to_integer()
    |> Repo.put_process_state()

    params
    |> Map.put(:organization_id, value)
    |> Map.delete(key)
  end

  @doc """
  A hack to suppress error messages when running lots of flows. These are expected
  and we want to improve signal <-> noise ratio
  """
  @spec ignore_error?(String.t()) :: boolean
  def ignore_error?(error) do
    # These errors are ok, and need not be reported to appsignal
    # to a large extent, its more a completion exit rather than an
    # error exit
    String.contains?(error, "Exit Loop") ||
      String.contains?(error, "finished the flow") ||
      String.contains?(error, "unexpected message received while waiting for time")
  end

  @doc """
  Log the error and also send it over to our friends at appsignal
  """
  @spec log_error(String.t(), boolean) :: {:error, String.t()}
  def log_error(error, send_appsignal? \\ true) do
    Logger.error(error)

    # disable sending exit loop and finished flow errors, since
    # these are beneficiary errors
    if !ignore_error?(error) && send_appsignal? do
      {_, stacktrace} = Process.info(self(), :current_stacktrace)
      Appsignal.send_error(:error, error, stacktrace)
    end

    {:error, error}
  end

  @doc """
  Handles logging and sending defexception erros to Appsignal
  """
  @spec log_exception(map()) :: :ok
  def log_exception(%{message: message} = error) when is_binary(message) do
    Logger.error(message)

    Appsignal.send_error(error, [])

    :ok
  end

  def log_exception(_error), do: :ok

  @doc """
  Verifying Google Captcha
  """
  @spec verify_google_captcha(String.t()) :: {:ok, String.t()} | {:error, any()}
  def verify_google_captcha(token) do
    create_request(token)
    |> then(&Tesla.post(@captcha_verify_url, &1))
    |> handle_response()
  end

  @spec create_request(String.t()) :: Tesla.Multipart.t()
  defp create_request(token) do
    Multipart.new()
    |> Multipart.add_field("secret", Application.get_env(:glific, :google_captcha_secret_key))
    |> Multipart.add_field("response", token)
  end

  @spec handle_response(tuple()) :: tuple()
  defp handle_response(response) do
    response
    |> case do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        response_body = Jason.decode!(body)

        if response_body["success"] && response_body["score"] > @captcha_score_threshold do
          {:ok, "success"}
        else
          captcha_error =
            response_body
            |> Map.get("error-codes", "Token verification failed")
            |> parse_captcha_error()

          Logger.info(
            "Failed to verify Google Captcha: #{captcha_error} and captcha score #{response_body["score"]}"
          )

          {:error, "Failed to verify Google Captcha: #{captcha_error}"}
        end

      {_status, response} ->
        Logger.info("Invalid response verifying Google Captcha: #{response}")
        {:error, "invalid response #{inspect(response)}"}
    end
  end

  defp parse_captcha_error(error) when is_binary(error), do: error
  defp parse_captcha_error(error), do: List.first(error)

  @doc """
  Adds a limit to restrict accessing data from big tables like messages, contacts
  which slows DB and takes longer to complete request

  Adding upper limit to 50 when limit is passed and is more than 50
  Adding limit to 25 when limit is not passed in args
  """
  @spec add_limit(map) :: map()
  def add_limit(%{opts: %{limit: limit}} = args) when limit > 50 do
    opts = Map.get(args, :opts, %{})

    Map.put(args, :opts, Map.put(opts, :limit, 50))
  end

  def add_limit(%{opts: %{limit: _limit}} = args), do: args

  def add_limit(%{opts: opts} = args), do: Map.put(args, :opts, Map.put(opts, :limit, 25))

  def add_limit(args), do: Map.put(args, :opts, Map.put(%{}, :limit, 25))

  @doc """
   Send template from expression from the flows
  """
  @spec send_template(String.t(), list()) :: binary
  def send_template(uuid, variables) do
    variables_list = Enum.map(variables, &to_string/1)

    %{
      uuid: uuid,
      variables: variables_list,
      expression: nil
    }
    |> Jason.encode!()
  end

  @doc """
  Get default OpenAI key
  """
  @spec get_open_ai_key() :: String.t()
  def get_open_ai_key do
    Application.get_env(:glific, :open_ai)
  end

  @doc """
  Get the Open AI ProjectID where we store Glific NGO's Assistants and VectorStores
  """
  @spec get_open_ai_project :: String.t()
  def get_open_ai_project do
    Application.get_env(:glific, :open_ai_project)
  end

  @doc """
  Get default Google Translate key
  """
  @spec get_google_translate_key() :: String.t()
  def get_google_translate_key do
    Application.get_env(:glific, :google_translate)
  end

  @doc """
  Get Bhashini keys
  """
  @spec get_bhashini_keys() :: map()
  def get_bhashini_keys do
    %{
      user_id: Application.get_env(:glific, :bhasini_user_id),
      ulca_api_key: Application.get_env(:glific, :bhasini_ulca_api_key),
      inference_key: Application.get_env(:glific, :bhasini_inference_key)
    }
  end

  @doc """
  Get Get Google Maps keys
  """
  @spec get_google_maps_api_key() :: String.t()
  def get_google_maps_api_key do
    Application.get_env(:glific, :google_maps_api_key)
  end

  @doc """
  mask last 5 digit of a phone number
  """
  @spec mask_phone_number(String.t()) :: String.t()
  def mask_phone_number(phone) when is_integer(phone) do
    phone
    |> Integer.to_string()
    |> mask_phone_number()
  end

  def mask_phone_number(phone) do
    {visible, masked} = String.split_at(phone, -5)
    visible <> String.replace(masked, ~r/\d/, "*")
  end

  @doc """
  the below 2 conditions are just for testing and prototyping purposes
  we'll get rid of them when we start using this actively
  """
  @spec trusted_env?(atom(), non_neg_integer()) :: boolean
  def trusted_env?(:dev, 1), do: true
  def trusted_env?(:prod, 2), do: true
  def trusted_env?(_env, _id), do: false

  @doc """
  Get the Glific organization id for the current environment.
  """
  @spec glific_organization_id() :: non_neg_integer()
  def glific_organization_id do
    app_env = Application.get_env(:glific, :environment)

    if app_env == :prod, do: 2, else: 1
  end

  @doc """
  Converts Tarams result into {:ok, map()} or {:error, String.t()}

  ## Examples

      iex> Glific.handle_tarams_result({:ok, %{a: "a"}})
      {:ok, %{a: "a"}}

      iex> Glific.handle_tarams_result({:error, %{a: ["is required"]}})
      {:error, "a is required"}
  """
  @spec handle_tarams_result({:ok, map()} | {:error, map()}) ::
          {:ok, map()} | {:error, String.t()}
  def handle_tarams_result({:error, error}) do
    Enum.map_join(error, ", ", fn {key, reason} ->
      "#{key} #{reason}"
    end)
    |> then(&{:error, &1})
  end

  def handle_tarams_result(result), do: result

  @doc """
  Returns a reusable, configurable Tesla retry middleware
  """
  @spec get_tesla_retry_middleware(%{
          optional(:retry_error_codes) => list(non_neg_integer()),
          optional(:retry_reasons) => list(any()),
          optional(:delay) => non_neg_integer(),
          optional(:max_retries) => non_neg_integer()
        }) :: list()
  def get_tesla_retry_middleware(retry_config \\ %{}) do
    retry_error_codes =
      [429, 500, 501, 502, 503, 504] ++ Map.get(retry_config, :retry_error_codes, [])

    reasons_to_retry =
      [:timeout, :connrefused, :nxdomain] ++ Map.get(retry_config, :retry_reasons, [])

    delay = Map.get(retry_config, :delay, 500)

    max_retries = Map.get(retry_config, :max_retries, 2)

    [
      {
        Tesla.Middleware.Retry,
        delay: delay,
        max_retries: max_retries,
        should_retry: fn
          {:ok, %{status: status}}, _, _ ->
            status in retry_error_codes

          {:error, reason}, _, _ ->
            reason in reasons_to_retry

          _, _, _ ->
            false
        end
      }
    ]
  end
end
