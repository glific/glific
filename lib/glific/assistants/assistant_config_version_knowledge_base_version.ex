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

  schema "assistant_config_version_knowledge_base_versions" do
    belongs_to(:assistant_config_version, AssistantConfigVersion)
    belongs_to(:knowledge_base_version, KnowledgeBaseVersion)
    belongs_to(:organization, Organization)

    timestamps(type: :utc_datetime)
  end
end
