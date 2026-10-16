defmodule Glific.Contacts.Channels do
  @moduledoc """
  Internal to `Glific.Contacts`, which is the only module that calls it. Reads and writes
  `Glific.Contacts.ContactChannel` rows: what a contact has agreed to on each channel.

  It never calls back into `Glific.Contacts`.
  """

  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactChannel,
    Enums.MessageChannel,
    Repo
  }

  @doc """
  The contact's state on a channel, if it has any.
  """
  @spec fetch(Contact.t(), MessageChannel.t()) :: {:ok, ContactChannel.t()} | {:error, :not_found}
  def fetch(%Contact{id: contact_id, organization_id: organization_id}, channel) do
    query =
      from(cc in ContactChannel,
        where:
          cc.contact_id == ^contact_id and cc.channel == ^channel and
            cc.organization_id == ^organization_id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      contact_channel -> {:ok, contact_channel}
    end
  end

  @doc """
  Whether the contact has opted in on the channel and not opted out since.
  """
  @spec opted_in?(Contact.t(), MessageChannel.t()) :: boolean()
  def opted_in?(contact, channel) do
    case fetch(contact, channel) do
      {:ok, %ContactChannel{optin_time: optin_time, optout_time: nil}} -> optin_time != nil
      _none_or_opted_out -> false
    end
  end

  @doc """
  Records an opt-in on a channel. The first call inserts the row and keeps its `optin_time` for
  good; a later call changes nothing, unless the contact had opted out, in which case it clears the
  opt-out. Tells the caller which of the three happened, so it can decide whether to log history.
  """
  @spec record_optin(Contact.t(), MessageChannel.t(), String.t() | nil, DateTime.t()) ::
          {:ok, ContactChannel.t(), :created | :reopted | :unchanged}
          | {:error, Ecto.Changeset.t()}
  def record_optin(%Contact{} = contact, channel, method, optin_time) do
    changeset =
      ContactChannel.changeset(%ContactChannel{}, %{
        contact_id: contact.id,
        organization_id: contact.organization_id,
        channel: channel,
        optin_time: DateTime.truncate(optin_time, :second),
        optin_method: method
      })

    # on_conflict: :nothing returns a struct without an id when the row already exists, which is
    # what lets two concurrent first opt-ins produce one `:created`.
    case Repo.insert(changeset, on_conflict: :nothing, conflict_target: [:contact_id, :channel]) do
      {:ok, %ContactChannel{id: id} = created} when not is_nil(id) -> {:ok, created, :created}
      {:ok, _conflict} -> contact |> fetch(channel) |> keep_or_reopt()
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec keep_or_reopt({:ok, ContactChannel.t()} | {:error, :not_found}) ::
          {:ok, ContactChannel.t(), :reopted | :unchanged} | {:error, Ecto.Changeset.t()}
  defp keep_or_reopt({:ok, %ContactChannel{optout_time: nil} = existing}),
    do: {:ok, existing, :unchanged}

  defp keep_or_reopt({:ok, %ContactChannel{} = existing}) do
    case existing
         |> ContactChannel.changeset(%{optout_time: nil, optout_method: nil})
         |> Ecto.Changeset.force_change(:optout_time, nil)
         |> Ecto.Changeset.force_change(:optout_method, nil)
         |> Repo.update() do
      {:ok, updated} -> {:ok, updated, :reopted}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp keep_or_reopt({:error, :not_found}),
    do:
      {:error,
       %ContactChannel{}
       |> Ecto.Changeset.change()
       |> Ecto.Changeset.add_error(:contact_id, "not found")}
end
