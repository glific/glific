defmodule Glific.AI.Tools.Reference do
  @moduledoc """
  The organisation's named things: tags, flow labels, contact fields, languages,
  collections, saved searches, certificate templates, global fields and roles.

  All nine answer one question — *what exists, and what is it called* — so they
  share a tool and the model picks the `kind`. Keeping them apart would spend
  nine of the assistant's tool slots on a single intent, and tool selection gets
  harder as the set grows.
  """

  alias Glific.{
    AccessControl,
    Certificates.CertificateTemplate,
    Flows.ContactField,
    Flows.FlowLabel,
    Groups,
    Partners,
    Repo,
    Searches,
    Settings,
    Tags
  }

  @behaviour Glific.AI.Tool

  @kinds ~w(tags flow_labels contact_fields languages collections saved_searches
            certificate_templates global_fields roles)

  @doc "The reference lookup this module offers."
  @impl Glific.AI.Tool
  @spec specs() :: [Glific.AI.Tool.spec()]
  def specs do
    [
      %{
        name: "list_reference",
        description: """
        Lists the organisation's named things, so a name in a question can be
        checked against what actually exists and resolved to an id. Pick the kind:

          * "tags" — tags applied to messages and contacts
          * "flow_labels" — labels flows apply to messages
          * "contact_fields" — contact field shortcodes and value types
          * "languages" — the languages available, which turn a language_id into a name
          * "collections" — the named sets contacts belong to, targeted by triggers and broadcasts
          * "saved_searches" — the searches staff use in the chat inbox
          * "certificate_templates" — certificates that can be issued from flows
          * "global_fields" — shared values flows read by key
          * "roles" — the roles staff can hold, which govern who may see what

        Use this before asserting that something exists, rather than assuming.
        """,
        parameters: [
          kind: [type: {:in, @kinds}, required: true, doc: "Which set of names to list"],
          limit: [type: :pos_integer, default: 50, doc: "How many to return, at most 200"]
        ]
      }
    ]
  end

  @doc "Reads one kind of the organisation's named things, so a name can be resolved to an id."
  @impl Glific.AI.Tool
  @spec run(String.t(), map()) :: {:ok, term()} | {:error, String.t()}
  def run("list_reference", %{kind: kind} = args), do: {:ok, list(kind, min(args[:limit], 200))}

  @spec list(String.t(), pos_integer()) :: [map()]
  defp list("tags", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> Tags.list_tags()
    |> Enum.map(&%{id: &1.id, label: &1.label, shortcode: &1.shortcode, parent_id: &1.parent_id})
  end

  defp list("flow_labels", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> FlowLabel.list_flow_labels()
    |> Enum.map(&%{id: &1.id, name: &1.name, type: &1.type})
  end

  defp list("contact_fields", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> ContactField.list_contacts_fields()
    |> Enum.map(
      &%{name: &1.name, shortcode: &1.shortcode, value_type: &1.value_type, scope: &1.scope}
    )
  end

  # These two contexts take no limit, so it is applied after the fact rather than
  # returning every row when a caller asked for a few.
  defp list("languages", limit) do
    Settings.list_languages()
    |> Enum.take(limit)
    |> Enum.map(&%{id: &1.id, label: &1.label, locale: &1.locale, is_active: &1.is_active})
  end

  defp list("collections", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> Groups.list_groups()
    |> Enum.map(
      &%{id: &1.id, label: &1.label, description: &1.description, group_type: &1.group_type}
    )
  end

  defp list("saved_searches", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> Searches.list_saved_searches()
    |> Enum.map(
      &%{id: &1.id, label: &1.label, shortcode: &1.shortcode, is_reserved: &1.is_reserved}
    )
  end

  defp list("certificate_templates", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0, order: :asc}}
    |> CertificateTemplate.list_certificate_templates()
    |> Enum.map(&%{id: &1.id, label: &1.label, description: &1.description, url: &1.url})
  end

  defp list("global_fields", limit) do
    %{filter: %{}, opts: %{limit: limit, offset: 0}}
    |> Partners.list_organization_data()
    |> Enum.map(&%{key: &1.key, description: &1.description, text: &1.text, json: &1.json})
  end

  defp list("roles", limit) do
    %{organization_id: Repo.get_organization_id()}
    |> AccessControl.list_roles()
    |> Enum.take(limit)
    |> Enum.map(
      &%{id: &1.id, label: &1.label, description: &1.description, is_reserved: &1.is_reserved}
    )
  end

  @doc false
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds
end
