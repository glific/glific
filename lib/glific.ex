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

  alias Glific.Partners

  @doc """
  Wrapper to return :ok/:error when parsing strings to potential integers
  """
  @spec parse_maybe_integer(String.t() | integer) :: {:ok, integer} | :error
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
  Validates inputed shortcode, if shortcode is invalid it returns message that the shortcode is invalid
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
  @spec atomize_keys(map()) :: map()
  def atomize_keys(nil), do: nil

  # Structs don't do enumerable and anyway the keys are already
  # atoms
  def atomize_keys(map) when is_struct(map),
    do: map

  def atomize_keys([head | rest]), do: [atomize_keys(head) | atomize_keys(rest)]

  def atomize_keys(map) when is_map(map),
    do:
      Enum.map(map, fn {k, v} ->
        if is_atom(k) do
          {atomize_keys(k), atomize_keys(v)}
        else
          {String.to_existing_atom(k), atomize_keys(v)}
        end
      end)
      |> Enum.into(%{})

  def atomize_keys(value), do: value

  @doc """
  easy way for glific developers to get a stacktrace when debugging
  """
  @spec stacktrace :: String.t()
  def stacktrace do
    {_, stacktrace} = Process.info(self(), :current_stacktrace)
    inspect(stacktrace)
  end

  @not_allowed ["Repo", "IO", "File", "Code"]

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
  Compute the signature at a specific time for the body
  """
  @spec signature(non_neg_integer, String.t(), non_neg_integer) :: String.t()
  def signature(organization_id, body, timestamp) do
    secret = Partners.organization(organization_id).signature_phrase

    signed_payload = "#{timestamp}.#{body}"
    hmac = :crypto.hmac(:sha256, secret, signed_payload)
    Base.encode16(hmac, case: :lower)
  end

  @doc false
  @spec validate_media?(String.t(), String.t()) :: boolean
  def validate_media?(url, type) do
    size_limit = %{
      "image" => 5120,
      "video" => 16384,
      "audio" => 16384,
      "document" => 102400,
      "sticker" => 100,
    }

    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: status, headers: headers}} when status in 200..299 ->
        headers
        |> Enum.reduce(%{}, fn header, acc -> Map.put(acc, elem(header, 0), elem(header, 1)) end)
        |> Map.put_new("content-type", "")
        |> IO.inspect()
        |> Map.put_new("content-length", 0)
        |> do_validate_headers(type, url, size_limit[type])

      _ ->
        false
    end
  end

  @spec do_validate_headers(map(), String.t(), String.t(), integer()) :: boolean
  defp do_validate_headers(headers, "document", _url, size_limit),
    do: String.contains?(headers["content-type"], "pdf")
    and do_validate_size(size_limit, headers["content-length"])

  defp do_validate_headers(headers, "sticker", _url, size_limit) do
    ## we might need to do some more changes in this. Currently I can find that this
    String.contains?(headers["content-type"], "image") and do_validate_size(size_limit, headers["content-length"])
  end

  defp do_validate_headers(headers, type, _url, size_limit) when type in ["image", "video", "audio"],
    do: String.contains?(headers["content-type"], type) and do_validate_size(size_limit, headers["content-length"])

  defp do_validate_headers(_, _, _, _), do: false

  @spec do_validate_size(Integer, String.t() | integer()) :: boolean
  defp do_validate_size(_size_limit, nil), do: false

  defp do_validate_size(size_limit, content_length) do
      {:ok, content_length} =  parse_maybe_integer(content_length)
      content_length_in_kb  = content_length/1024
      size_limit >= content_length_in_kb
  end

end
