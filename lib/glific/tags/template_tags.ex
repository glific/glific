defmodule Glific.Tags.TemplateTags do
  @moduledoc """
  Simple container to hold all the template tags we associate with one template
  """

  alias __MODULE__

  alias Glific.{
    Tags,
    Tags.TemplateTag
  }

  use Ecto.Schema

  @primary_key false

  @type t() :: %__MODULE__{
          template_tags: [TemplateTag.t()],
          number_deleted: non_neg_integer
        }

  embedded_schema do
    # the number of tags we deleted
    field :number_deleted, :integer, default: 0
    embeds_many(:template_tags, TemplateTag)
  end

  @doc """
  Creates and/or deletes a list of template tags, each tag attached to the same template
  """
  @spec update_template_tags(map()) :: TemplateTags.t()
  def update_template_tags(
        %{template_id: template_id, add_tag_ids: add_ids, delete_tag_ids: delete_ids} = attrs
      ) do
    # we'll ignore errors intentionally here. the return list indicates
    # what objects we created
    template_tags =
      Enum.reduce(
        add_ids,
        [],
        fn tag_id, acc ->
          case Tags.create_template_tag(Map.put(attrs, :tag_id, tag_id)) do
            {:ok, template_tag} -> [template_tag | acc]
            _ -> acc
          end
        end
      )

    {number_deleted, _} = Tags.delete_template_tag_by_ids(template_id, delete_ids)

    %TemplateTags{
      number_deleted: number_deleted,
      template_tags: template_tags
    }
  end
end
