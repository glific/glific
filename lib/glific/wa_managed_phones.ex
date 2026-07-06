defmodule Glific.WAManagedPhones do
  @moduledoc """
  The WAGroup context.
  """

  import Ecto.Query, warn: false

  alias Glific.{
    Contacts,
    Notifications,
    Providers.Maytapi.ApiClient,
    Repo,
    SafeLog,
    WAGroup.WAManagedPhone
  }

  @healthy_statuses ["active", "loading"]
  @screen_ttl_seconds 15

  @doc """
  Returns the list of wa_managed_phones.

  ## Examples

      iex> list_wa_managed_phones()
      [%WAManagedPhone{}, ...]

  """
  @spec list_wa_managed_phones(map()) :: [WAManagedPhone.t()]
  def list_wa_managed_phones(args) do
    args
    |> Repo.list_filter_query(WAManagedPhone, &Repo.opts_with_inserted_at/2, &Repo.filter_with/2)
    |> Repo.all()
  end

  @doc """
  Return the count of wa_managed_phones, using the same filter as list_wa_managed_phones
  """
  @spec count_wa_managed_phones(map()) :: integer
  def count_wa_managed_phones(args),
    do: Repo.count_filter(args, WAManagedPhone, &Repo.filter_with/2)

  @doc """
  Gets a single wa_managed_phone.

  Raises `Ecto.NoResultsError` if the Wa managed phone does not exist.

  ## Examples

      iex> get_wa_managed_phone!(123)
      %WAManagedPhone{}

      iex> get_wa_managed_phone!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_wa_managed_phone!(non_neg_integer()) :: WAManagedPhone.t()
  def get_wa_managed_phone!(id), do: Repo.get!(WAManagedPhone, id)

  @doc """
  Gets a single wa_managed_phone.

  Returns nil if the Wa managed phone does not exist.

  ## Examples

      iex> get_wa_managed_phone(45323)
      %WAManagedPhone{}

      iex> get_wa_managed_phone(156)
      ** nil

  """
  @spec get_wa_managed_phone(non_neg_integer()) :: WAManagedPhone.t() | nil
  def get_wa_managed_phone(phone_id) do
    from(p in WAManagedPhone,
      where: p.phone_id == ^phone_id
    )
    |> Repo.one()
  end

  @doc """
  Fetch a managed phone by phone number.
  Used by the inbound webhook path to resolve Maytapi's `receiver` field
  into the WA managed phone that received the message.
  """
  @spec fetch_by_phone(String.t()) ::
          {:ok, WAManagedPhone.t()} | {:error, [String.t()]}
  def fetch_by_phone(phone) do
    Repo.fetch_by(WAManagedPhone, %{phone: phone})
  end

  @doc """
  Creates a wa_managed_phone.

  ## Examples

      iex> create_wa_managed_phone(%{field: value})
      {:ok, %WAManagedPhone{}}

      iex> create_wa_managed_phone(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_wa_managed_phone(map()) :: {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def create_wa_managed_phone(attrs \\ %{}) do
    %WAManagedPhone{}
    |> WAManagedPhone.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a wa_managed_phone.

  ## Examples

      iex> update_wa_managed_phone(wa_managed_phone, %{field: new_value})
      {:ok, %WAManagedPhone{}}

      iex> update_wa_managed_phone(wa_managed_phone, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_wa_managed_phone(WAManagedPhone.t(), map()) ::
          {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def update_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone, attrs) do
    wa_managed_phone
    |> WAManagedPhone.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a wa_managed_phone.

  ## Examples

      iex> delete_wa_managed_phone(wa_managed_phone)
      {:ok, %WAManagedPhone{}}

      iex> delete_wa_managed_phone(wa_managed_phone)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_wa_managed_phone(WAManagedPhone.t()) ::
          {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  def delete_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone) do
    Repo.delete(wa_managed_phone)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking wa_managed_phone changes.

  ## Examples

      iex> change_wa_managed_phone(wa_managed_phone)
      %Ecto.Changeset{data: %WAManagedPhone{}}

  """
  @spec change_wa_managed_phone(WAManagedPhone.t(), map()) :: Ecto.Changeset.t()
  def change_wa_managed_phone(%WAManagedPhone{} = wa_managed_phone, attrs \\ %{}) do
    WAManagedPhone.changeset(wa_managed_phone, attrs)
  end

  @doc """
  Deletes the existing WhatsApp data for an org
  """
  @spec delete_existing_wa_managed_phones(non_neg_integer()) :: :ok
  def delete_existing_wa_managed_phones(org_id) do
    WAManagedPhone
    |> where([wam], wam.organization_id == ^org_id)
    |> Repo.delete_all(organization_id: org_id, timeout: 600_000)

    :ok
  end

  @doc """
  fetches WhatsApp enabled phone added in Maytapi account
  """
  @spec fetch_wa_managed_phones(non_neg_integer()) :: :ok | {:error, String.t()}
  def fetch_wa_managed_phones(org_id) do
    with {:ok, secrets} <- ApiClient.fetch_credentials(org_id),
         {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_managed_phones(org_id),
         {:ok, response} <- Jason.decode(body),
         {:ok, wa_managed_phones} <- validate_response(response) do
      Enum.each(wa_managed_phones, fn wa_managed_phone ->
        upsert_wa_managed_phone(wa_managed_phone, org_id, secrets["product_id"])
      end)

      ensure_active_phone(wa_managed_phones)
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec upsert_wa_managed_phone(map(), non_neg_integer(), String.t()) :: {:ok, String.t()}
  defp upsert_wa_managed_phone(attrs, org_id, product_id) do
    case attrs["number"] do
      phone when is_binary(phone) and phone != "" ->
        upsert_connected_phone(attrs, phone, org_id, product_id)

      _ ->
        refresh_logged_out_phone(attrs)
    end
  end

  @spec upsert_connected_phone(map(), String.t(), non_neg_integer(), String.t()) ::
          {:ok, String.t()}
  defp upsert_connected_phone(attrs, phone, org_id, product_id) do
    status = attrs["status"]

    params = %{
      label: attrs["name"],
      phone: phone,
      phone_id: attrs["id"],
      product_id: product_id,
      organization_id: org_id,
      contact_type: "WA"
    }

    result =
      with {:ok, contact} <- Contacts.maybe_create_contact(params),
           nil <- Repo.get_by(WAManagedPhone, %{phone: phone, organization_id: org_id}) do
        params
        |> Map.merge(%{contact_id: contact.id, status: status})
        |> create_wa_managed_phone()
      else
        %WAManagedPhone{} = existing -> reconcile_status(existing, status)
        {:error, _reason} = error -> error
      end

    log_upsert_error(result, phone, org_id)
  end

  # Logged-out phone: known phone_id, no number (Maytapi returns "idle"). Can't
  # create a contact without a number, so just refresh the existing row's status.
  @spec refresh_logged_out_phone(map()) :: {:ok, String.t()}
  defp refresh_logged_out_phone(%{"id" => phone_id, "status" => status})
       when not is_nil(phone_id) do
    case get_wa_managed_phone(phone_id) do
      %WAManagedPhone{} = existing ->
        existing
        |> reconcile_status(status)
        |> log_upsert_error(existing.phone, existing.organization_id)

      nil ->
        {:ok, "success"}
    end
  end

  defp refresh_logged_out_phone(_attrs), do: {:ok, "skipped"}

  @spec log_upsert_error({:ok, any()} | {:error, any()}, String.t(), non_neg_integer()) ::
          {:ok, String.t()}
  defp log_upsert_error({:error, error}, phone, org_id) do
    Glific.log_error(
      "Failed to sync Maytapi phone #{phone} for org #{org_id}: #{SafeLog.safe_inspect(error)}"
    )

    {:ok, "success"}
  end

  defp log_upsert_error(_result, _phone, _org_id), do: {:ok, "success"}

  @spec validate_response(list() | map()) :: {:ok, list()} | {:error, String.t()}
  defp validate_response(wa_managed_phones) when is_list(wa_managed_phones),
    do: {:ok, wa_managed_phones}

  defp validate_response(%{"message" => message, "success" => false}),
    do: {:error, message}

  defp validate_response(_), do: {:error, "Something went wrong"}

  @spec ensure_active_phone(list()) :: :ok | {:error, String.t()}
  defp ensure_active_phone(wa_managed_phones) do
    if Enum.any?(wa_managed_phones, &(&1["status"] == "active")),
      do: :ok,
      else: {:error, "No active phones available"}
  end

  @doc """
  Reconciles a single phone's status from Maytapi's real-time status webhook.
  """
  @spec status(String.t(), non_neg_integer()) :: {:ok, WAManagedPhone.t()} | {:error, String.t()}
  def status(new_status, phone_id) do
    with %WAManagedPhone{} = phone <- get_wa_managed_phone(phone_id),
         {:ok, updated} <- reconcile_status(phone, new_status) do
      {:ok, updated}
    else
      nil ->
        {:error, "Phone ID not found"}

      {:error, changeset} ->
        {:error, "Failed to update status: #{SafeLog.safe_inspect(changeset.errors)}"}
    end
  end

  @doc """
  Polls Maytapi for the latest phone statuses and reconciles them against the
  stored `wa_managed_phones` rows, alerting on transitions into unhealthy states.

  Unlike `fetch_wa_managed_phones/1` this never provisions new phones/contacts —
  it only refreshes the health of phones Glific already knows about, so it is
  safe to run on a schedule.
  """
  @spec reconcile_wa_managed_phone_statuses(non_neg_integer()) :: :ok | {:error, String.t()}
  def reconcile_wa_managed_phone_statuses(org_id) do
    with {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 <-
           ApiClient.list_wa_managed_phones(org_id),
         {:ok, response} <- Jason.decode(body),
         {:ok, phones} <- validate_response(response) do
      Enum.each(phones, &reconcile_known_phone(&1, org_id))
      :ok
    else
      {:error, error} -> {:error, error}
      _ -> {:error, "Could not reconcile WhatsApp phone statuses"}
    end
  end

  @spec reconcile_known_phone(map(), non_neg_integer()) :: :ok
  defp reconcile_known_phone(%{"id" => phone_id, "status" => new_status}, org_id)
       when not is_nil(phone_id) do
    with %WAManagedPhone{} = phone <-
           Repo.get_by(WAManagedPhone, %{phone_id: phone_id, organization_id: org_id}),
         {:ok, _updated} <- reconcile_status(phone, to_string(new_status)) do
      :ok
    else
      nil ->
        :ok

      {:error, changeset} ->
        Glific.log_error(
          "Failed to reconcile status for phone_id #{phone_id} (org #{org_id}): #{SafeLog.safe_inspect(changeset.errors)}"
        )

        :ok
    end
  end

  defp reconcile_known_phone(_attrs, _org_id), do: :ok

  # Updates a known phone's status, stamps the check time, and alerts only when
  # the status *transitions* into a bad state — so a phone that stays
  # disconnected doesn't re-notify on every webhook/poll.
  @spec reconcile_status(WAManagedPhone.t(), String.t() | nil) ::
          {:ok, WAManagedPhone.t()} | {:error, Ecto.Changeset.t()}
  defp reconcile_status(%WAManagedPhone{} = phone, new_status) do
    previous_status = phone.status

    with {:ok, updated} <-
           update_wa_managed_phone(phone, %{
             status: new_status,
             last_status_checked_at: DateTime.utc_now()
           }) do
      maybe_alert_status_transition(previous_status, updated)
      {:ok, updated}
    end
  end

  @doc """
  Whether a Maytapi status means the phone can still send/receive messages.
  """
  @spec healthy_status?(String.t() | nil) :: boolean()
  def healthy_status?(status), do: status in @healthy_statuses

  @spec maybe_alert_status_transition(String.t() | nil, WAManagedPhone.t()) :: :ok
  defp maybe_alert_status_transition(previous_status, %WAManagedPhone{status: new_status} = phone) do
    if not healthy_status?(new_status) and new_status != previous_status do
      severity = status_severity(new_status)

      Notifications.create_notification(%{
        category: "WhatsApp Groups",
        message: status_alert_message(phone, severity),
        severity: severity,
        organization_id: phone.organization_id,
        entity: %{phone: phone.phone, status: new_status}
      })
    end

    :ok
  end

  # A phone suspended/banned by WhatsApp (Meta) is critical — unusable until
  # restored. A plain Maytapi disconnect is a warning: the admin can reconnect it
  # from Glific.
  @spec status_severity(String.t() | nil) :: String.t()
  defp status_severity(status) do
    normalized = status |> to_string() |> String.downcase()

    if String.contains?(normalized, "ban") or String.contains?(normalized, "suspend"),
      do: Notifications.types().critical,
      else: Notifications.types().warning
  end

  @spec status_alert_message(WAManagedPhone.t(), String.t()) :: String.t()
  defp status_alert_message(%WAManagedPhone{phone: phone, status: status}, severity) do
    if severity == Notifications.types().critical do
      "WhatsApp phone #{phone} appears suspended by WhatsApp (status: #{status}). Messaging is blocked until it is restored."
    else
      "WhatsApp phone #{phone} is disconnected (status: #{status}). Reconnect it from the WhatsApp Phones page to resume messaging."
    end
  end

  @doc """
  Fetches the QR / login screen for a managed phone so an admin can reconnect it
  without logging into the Maytapi console. Returns the QR payload plus a refresh
  hint (`expires_at`).
  """
  @spec fetch_phone_screen(non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, String.t()}
  def fetch_phone_screen(org_id, wa_managed_phone_id) do
    with {:ok, %WAManagedPhone{} = phone} <-
           Repo.fetch_by(WAManagedPhone, %{id: wa_managed_phone_id, organization_id: org_id}),
         {:ok, code} <- ApiClient.fetch_phone_screen(org_id, phone.phone_id) do
      {:ok,
       %{
         code: code,
         status: phone.status,
         expires_at: DateTime.add(DateTime.utc_now(), @screen_ttl_seconds, :second)
       }}
    else
      {:error, [_ | _] = messages} -> {:error, Enum.join(messages, ", ")}
      {:error, error} when is_binary(error) -> {:error, error}
      _ -> {:error, "Could not fetch the WhatsApp login screen. Please try again."}
    end
  end

  @doc """
  Logs a managed phone out of WhatsApp so Maytapi issues a fresh QR/login screen.
  The frontend then polls `fetch_phone_screen/2` and shows the QR to rescan.
  """
  @spec reconnect_wa_managed_phone(non_neg_integer(), non_neg_integer()) ::
          {:ok, WAManagedPhone.t()} | {:error, String.t()}
  def reconnect_wa_managed_phone(org_id, wa_managed_phone_id) do
    with {:ok, %WAManagedPhone{} = phone} <-
           Repo.fetch_by(WAManagedPhone, %{id: wa_managed_phone_id, organization_id: org_id}),
         false <- phone.status == "active",
         :ok <- ApiClient.logout_phone(org_id, phone.phone_id) do
      {:ok, phone}
    else
      true -> {:error, "This WhatsApp phone is already connected."}
      {:error, [_ | _] = messages} -> {:error, Enum.join(messages, ", ")}
      {:error, error} when is_binary(error) -> {:error, error}
      _ -> {:error, "Could not start reconnect. Please try again."}
    end
  end
end
