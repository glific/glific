defmodule Glific.TemplateRephrase do
  @moduledoc """
  Context for on-demand WhatsApp template body rephrasing.

  A user supplies a template body and one of three actions (professional, utility,
  custom); this context calls Kaapi's async LLM service and persists the request.
  When Kaapi completes, it POSTs back to `/kaapi/template_rephrase` and
  `handle_callback/1` updates the row.

  ## Flow

      1. `rephrase/3` — build payload, call Kaapi, persist `:in_progress` row.
      2. Kaapi processes asynchronously and POSTs to the callback URL.
      3. `handle_callback/1` — look up by `metadata.request_id`, update status + text/error.

  ## Callback correlation

  We generate a UUID `request_id` before calling Kaapi and embed it as
  `request_metadata.request_id` in the payload. Kaapi echoes it back as
  `metadata.request_id` in the async callback body — this is the correlation key.
  """

  import Glific.SafeLog

  alias Glific.{
    Partners,
    Repo,
    TemplateRephrase.TemplateRephraseRequest,
    ThirdParty.Kaapi
  }

  defmodule Error do
    @moduledoc """
    Custom error for template-rephrase failures.

    The callback endpoint is a backend-to-backend integration with Kaapi (users
    never interact with it), so failures are reported to AppSignal under the
    `"template_rephrase"` namespace rather than surfaced to a user. This lets us
    build an error-rate trigger on the namespace.
    """
    defexception [:message, :reason, :organization_id]

    @spec message(%__MODULE__{}) :: String.t()
    def message(%Error{} = error) do
      "#{error.message} reason: #{error.reason} organization_id: #{error.organization_id}"
    end
  end

  @appsignal_namespace "template_rephrase"

  @placeholder_rule "Preserve every WhatsApp placeholder variable (e.g. {{1}}, {{2}}) exactly as given — never rename, remove, renumber, or add placeholders."

  @return_rule "Return only the rewritten message text. No explanation, no quotes, no preamble."

  @professional_prompt """
  You are an expert copywriter helping rewrite a WhatsApp business message template body
  in a professional, polished tone suitable for business communication.

  Rewrite the given message so it reads as clear, professional, and courteous, while
  preserving its original meaning and intent. Do not pad or artificially lengthen the
  message — keep it close to its original length.

  #{@placeholder_rule}

  #{@return_rule}
  """

  @utility_prompt """
  You are an expert copywriter helping rewrite a WhatsApp business message template body
  so it fits WhatsApp's "Utility" template category, per Meta's messaging policy.

  Utility messages are strictly transactional or informational — for example order
  updates, appointment reminders, account alerts, or confirmations. Rewrite the given
  message to remove any promotional or marketing language, discounts, urgency hype, or
  calls to purchase. Keep the tone clear, neutral, and factual.

  #{@placeholder_rule}

  #{@return_rule}
  """

  @doc """
  Initiates async rephrasing for the given WhatsApp template body.

  Builds the Kaapi LLM payload (including a unique `request_id` and `callback_url`),
  calls Kaapi, then persists a `:in_progress` `TemplateRephraseRequest` row.
  Returns `{:ok, request}` on success.

  The `request_id` (a UUID we generate) is stored on the row and sent to Kaapi as
  `request_metadata.request_id`. Kaapi echoes it back in the async callback as
  `metadata.request_id` — this is the correlation key.

  Returns `{:error, reason}` — without inserting a row — when Kaapi is inactive for
  the org or when the Kaapi call itself fails.

  The `:is_template_ai_assist_enabled` feature flag gates access to this function at the
  GraphQL mutation layer. The flag is registered in `Glific.Flags` and exposed via the
  organization schema.

  ## Parameters

    - `params` — map with keys `:text` (the template body), `:action`
      (`:professional`, `:utility`, or `:custom`), and `:custom_prompt` (required only
      when `:action` is `:custom`).
    - `org_id` — organization ID (scopes the row and the Kaapi credential lookup).
    - `user_id` — optional user who initiated the request; stored for audit.

  ## Examples

      iex> Glific.TemplateRephrase.rephrase(%{text: "Hi {{1}}, your order shipped!", action: :professional, custom_prompt: nil}, 1)
      {:ok, %TemplateRephraseRequest{status: :in_progress, ...}}
  """
  @spec rephrase(map(), non_neg_integer(), non_neg_integer() | nil) ::
          {:ok, TemplateRephraseRequest.t()} | {:error, any()}
  def rephrase(
        %{text: text, action: action, custom_prompt: custom_prompt},
        org_id,
        user_id \\ nil
      ) do
    request_id = Ecto.UUID.generate()
    callback_url = build_callback_url(org_id)
    payload = build_llm_payload(text, action, custom_prompt, callback_url, request_id)

    with {:ok, _ack} <- Kaapi.rephrase_template_body(payload, org_id) do
      create_rephrase_request(%{
        original_text: text,
        action: action,
        custom_prompt: custom_prompt,
        status: :in_progress,
        request_id: request_id,
        organization_id: org_id,
        user_id: user_id
      })
    end
  end

  @doc """
  Handles the async callback POSTed by Kaapi after LLM completion.

  Looks up the `TemplateRephraseRequest` by `metadata.request_id` (the UUID we
  generated and sent to Kaapi in `request_metadata.request_id`; Kaapi echoes it back).
  On `success: true`, sets `status: :ready` and `rephrased_text`. On failure
  (`success: false` or error present), sets `status: :failed` and `error_message`.
  Unknown `request_id` logs and returns an error.

  This function is idempotent: calling it twice on the same row is safe — the
  terminal-state guard returns `{:ok, request}` unchanged for rows already in
  `:ready` or `:failed`.

  The real callback shape (string-keyed after Plug JSON parsing):

  ```json
  {
    "success": true,
    "data": {
      "response": {
        "output": { "content": { "value": "<rephrased text>" } }
      }
    },
    "metadata": { "request_id": "<uuid we sent>" }
  }
  ```

  ## Parameters

    - `params` — the parsed JSON body from Kaapi (string-keyed).
  """
  @spec handle_callback(map()) ::
          {:ok, TemplateRephraseRequest.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def handle_callback(%{"metadata" => %{"request_id" => request_id}} = params) do
    with {:ok, request} <- Repo.fetch_by(TemplateRephraseRequest, %{request_id: request_id}),
         {:ok, updated} <- apply_callback(request, params) do
      {:ok, updated}
    else
      {:error, [_, "Resource not found"]} ->
        log_callback_error("No template rephrase request found for the callback",
          reason: "request_id=#{request_id}"
        )

        {:error, "Template rephrase request not found for request_id=#{request_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def handle_callback(params) do
    log_callback_error("Unexpected template rephrase callback payload",
      reason: safe_inspect(params)
    )

    {:error, "Unexpected template rephrase callback payload"}
  end

  @doc """
  Builds the Kaapi LLM API payload for template-body rephrasing.

  The `query.input` field is the original template text. The `config` blob specifies
  the OpenAI `gpt-4o` completion, with `instructions` chosen from the action's system
  prompt (or the interpolated custom prompt). The callback URL and a unique
  `request_id` (for correlation) are embedded in the envelope.

  ## Examples

      iex> Glific.TemplateRephrase.build_llm_payload("Hi {{1}}", :professional, nil, "https://cb.url", "uuid-123")
      %{query: %{input: "Hi {{1}}"}, config: %{...}, callback_url: "https://cb.url", ...}
  """
  @spec build_llm_payload(String.t(), atom(), String.t() | nil, String.t(), String.t()) :: map()
  def build_llm_payload(text, action, custom_prompt, callback_url, request_id) do
    %{
      query: %{input: text},
      config: %{
        blob: %{
          completion: %{
            provider: "openai",
            type: "text",
            params: %{
              model: "gpt-4o",
              instructions: instructions_for(action, custom_prompt),
              temperature: 0.4
            }
          }
        }
      },
      callback_url: callback_url,
      request_metadata: %{request_id: request_id}
    }
  end

  @doc """
  Returns the system-prompt instructions for the given rephrase action.

  For `:custom`, the user's free-text `custom_prompt` is interpolated into a wrapper
  prompt that carries the same placeholder-preservation and output-format rules.

  ## Examples

      iex> Glific.TemplateRephrase.instructions_for(:professional, nil) =~ "professional"
      true
  """
  @spec instructions_for(atom(), String.t() | nil) :: String.t()
  def instructions_for(:professional, _custom_prompt), do: @professional_prompt
  def instructions_for(:utility, _custom_prompt), do: @utility_prompt

  def instructions_for(:custom, custom_prompt) do
    """
    You are an expert copywriter helping rewrite a WhatsApp business message template body
    according to the following instruction from the user:

    "#{custom_prompt}"

    Apply this instruction to rewrite the given message.

    #{@placeholder_rule}

    #{@return_rule}
    """
  end

  @spec create_rephrase_request(map()) ::
          {:ok, TemplateRephraseRequest.t()} | {:error, Ecto.Changeset.t()}
  defp create_rephrase_request(attrs) do
    %TemplateRephraseRequest{}
    |> TemplateRephraseRequest.changeset(attrs)
    |> Repo.insert()
  end

  @spec apply_callback(TemplateRephraseRequest.t(), map()) ::
          {:ok, TemplateRephraseRequest.t()} | {:error, Ecto.Changeset.t()}
  defp apply_callback(%TemplateRephraseRequest{status: status} = request, _params)
       when status in [:ready, :failed],
       do: {:ok, request}

  defp apply_callback(request, %{"success" => true} = params) do
    rephrased_text = get_in(params, ["data", "response", "output", "content", "value"])

    request
    |> TemplateRephraseRequest.changeset(%{
      status: :ready,
      rephrased_text: rephrased_text
    })
    |> Repo.update()
    |> record_outcome("success")
  end

  defp apply_callback(request, params) do
    error_message =
      case params["error"] do
        nil -> safe_inspect(params["errors"])
        msg -> msg
      end

    request
    |> TemplateRephraseRequest.changeset(%{
      status: :failed,
      error_message: error_message
    })
    |> Repo.update()
    |> record_outcome("failure")
  end

  @spec record_outcome(
          {:ok, TemplateRephraseRequest.t()} | {:error, Ecto.Changeset.t()},
          String.t()
        ) :: {:ok, TemplateRephraseRequest.t()} | {:error, Ecto.Changeset.t()}
  defp record_outcome({:ok, request} = result, status) do
    duration_ms = DateTime.diff(DateTime.utc_now(), request.inserted_at, :millisecond)
    Appsignal.increment_counter("template_rephrase_count", 1, %{status: status})
    Appsignal.add_distribution_value("template_rephrase_latency", duration_ms, %{status: status})
    result
  end

  defp record_outcome({:error, changeset} = result, status) do
    log_callback_error("Failed to persist template rephrase as :#{status}",
      reason: safe_inspect(changeset)
    )

    result
  end

  defp record_outcome(result, _status), do: result

  @spec log_callback_error(String.t(), keyword()) :: :ok
  defp log_callback_error(message, opts) do
    Glific.log_exception(
      %Error{message: message, reason: Keyword.get(opts, :reason)},
      namespace: @appsignal_namespace
    )
  end

  @spec build_callback_url(non_neg_integer()) :: String.t()
  defp build_callback_url(org_id) do
    organization = Partners.organization(org_id)
    Glific.api_callback_base(organization.shortcode) <> "/kaapi/template_rephrase"
  end
end
