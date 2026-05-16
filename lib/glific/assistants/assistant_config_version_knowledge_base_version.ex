defmodule Glific.Assistants.AssistantConfigVersionKnowledgeBaseVersion do
  @moduledoc """
  Join table schema for assistant config versions and knowledge base versions
  """

  use Ecto.Schema

  alias Glific.{
    Assistants.AssistantConfigVersion,
    Assistants.KnowledgeBaseVersion,
    Partners.Organization
  }

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: non_neg_integer() | nil,
          assistant_config_version_id: non_neg_integer() | nil,
          knowledge_base_version_id: non_neg_integer() | nil,
          organization_id: non_neg_integer() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "assistant_config_version_knowledge_base_versions" do
    belongs_to(:assistant_config_version, AssistantConfigVersion)
    belongs_to(:knowledge_base_version, KnowledgeBaseVersion)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end
end
