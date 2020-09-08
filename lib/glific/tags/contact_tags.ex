defmodule Glific.Tags.ContactTags do
  @moduledoc """
  Simple container to hold all the contact tags we associate with one contact
  """

  alias __MODULE__

  alias Glific.{
    Tags,
    Tags.ContactTag
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          contact_tags: [ContactTag.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of tags we deleted
    field :number_deleted, :integer, default: 0
    embeds_many(:contact_tags, ContactTag)
  end

  @doc """
  Creates and/or deletes a list of contact tags, each tag attached to the same contact
  """
  @spec update_contact_tags(map()) :: ContactTags.t()
  def update_contact_tags(
        %{contact_id: contact_id, add_tag_ids: add_ids, delete_tag_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    contact_tags =
      Enum.reduce(
        add_ids,
        [],
        fn tag_id, acc ->
          case Tags.create_contact_tag(Map.put(attrs, :tag_id, tag_id)) do
            {:ok, contact_tag} -> [contact_tag | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Tags.delete_contact_tag_by_ids(contact_id, delete_ids)

    %ContactTags{
      number_deleted: number_deleted,
      contact_tags: contact_tags
    }
  end
end
