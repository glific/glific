defmodule Glific.Seeds.Seeds20250826044001AddLangfuseProvider do
  use Glific.Seeds.Seed

  import Ecto.Query

  alias Glific.{
    Partners.Provider,
    Repo
  }

  envs([:dev, :test, :prod])

  tags([:langfuse])

  def up(_repo, _opts) do
    add_langfuse()
  end

  def down(_repo, _opts) do
    from(p in Provider, where: p.shortcode == "langfuse")
    |> Repo.delete_all()
  end

  @spec add_langfuse() :: any()
  defp add_langfuse() do
    query = from(p in Provider, where: p.shortcode == "langfuse")

    if !Repo.exists?(query),
      do:
        Repo.insert!(%Provider{
          name: "Langfuse",
          shortcode: "langfuse",
          description:
            "Open-source LLM engineering platform for collaborative debugging, analysis, and iteration on LLM applications.",
          group: nil,
          is_required: false,
          keys: %{},
          secrets: %{
            api_key: %{
              type: :string,
              label: "API Key",
              default: nil,
              view_only: false
            }
          }
        })
  end
end
