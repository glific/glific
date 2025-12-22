defmodule Glific.Mails.MailLog do
  @moduledoc """
  The mail log object
  """
  use Ecto.Schema
  import Ecto.Changeset

  import Ecto.Query, warn: false

  alias __MODULE__

  alias Glific.{
    Partners.Organization,
    Repo
  }

  @required_fields [:category, :organization_id]
  @optional_fields [:status, :content, :error]

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer | nil,
          category: String.t() | nil,
          status: String.t() | nil,
          content: map() | nil,
          organization_id: non_neg_integer | nil,
          organization: Organization.t() | Ecto.Association.NotLoaded.t() | nil,
          inserted_at: :utc_datetime | nil,
          updated_at: :utc_datetime | nil
        }

  schema "mail_logs" do
    field(:category, :string)
    field(:status, :string)
    field(:content, :map, default: %{})
    field(:error, :string)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Standard changeset pattern we use for all data types
  """
  @spec changeset(MailLog.t(), map()) :: Ecto.Changeset.t()
  def changeset(mail_log, attrs) do
    mail_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end

  @doc """
  Create a Mail Log
  """
  @spec create_mail_log(map()) :: {:ok, MailLog.t()} | {:error, Ecto.Changeset.t()}
  def create_mail_log(attrs \\ %{}) do
    %MailLog{}
    |> MailLog.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a Mail Log
  """
  @spec update_mail_log(MailLog.t(), map()) ::
          {:ok, MailLog.t()} | {:error, Ecto.Changeset.t()}
  def update_mail_log(log, attrs) do
    log
    |> MailLog.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns the list of mail logs.
  Since this is very basic and only listing functionality we added the status filter like this.
  In future we will put the status as virtual filed in the mail logs itself.
  """
  @spec list_mail_logs(map(), list()) :: list()
  def list_mail_logs(args, opts \\ []) do
    Repo.list_filter(args, MailLog, &Repo.opts_with_inserted_at/2, &filter_with/2, opts)
  end

  @spec filter_with(Ecto.Queryable.t(), %{optional(atom()) => any}) :: Ecto.Queryable.t()
  defp filter_with(query, filter) do
    query = Repo.filter_with(query, filter)

    Enum.reduce(filter, query, fn
      {:category, category}, query ->
        from(q in query, where: ilike(q.category, ^"%#{category}%"))

      _, query ->
        query
    end)
  end

  @doc """
  Return the count of mail_logs, using the same filter as list_mail_logs
  """
  @spec count_mail_logs(map()) :: integer
  def count_mail_logs(args),
    do: Repo.count_filter(args, MailLog, &filter_with/2)

  @doc """
  Check if we have sent the mail in given time
  """

  @spec mail_sent_in_past_time?(String.t(), DateTime.t(), non_neg_integer(), String.t() | nil) ::
          boolean
  def mail_sent_in_past_time?(category, time, organization_id, message_body \\ nil)

  def mail_sent_in_past_time?("critical_notification", time, organization_id, message_body) do
    # for critical notifications, we have to check the mail body to make sure
    # we are not skipping unique messages
    count =
      MailLog
      |> where([ml], ml.category == "critical_notification")
      |> where([ml], ml.organization_id == ^organization_id)
      |> where([ml], ml.inserted_at >= ^time)
      |> Repo.all()
      |> Enum.count(fn mail_log ->
        # using Code.eval_string, because we use Kernel.inspect for dumping the data in DB
        {content, _} = Code.eval_string(mail_log.content["data"])
        content[:text_body] == message_body
      end)

    count > 0
  end

  def mail_sent_in_past_time?(category, time, organization_id, _message_body) do
    count =
      MailLog
      |> where([ml], ml.category == ^category)
      |> where([ml], ml.organization_id == ^organization_id)
      |> where([ml], ml.inserted_at >= ^time)
      |> Repo.aggregate(:count)

    count > 0
  end
end
