defmodule Glific.Templates.InteractiveTemplateTest do
  use Glific.DataCase, async: true

  alias Glific.Repo
  alias Glific.Templates.InteractiveTemplate

  import Glific.Fixtures

  describe "changeset/2" do
    test "valid interactive_template", %{organization_id: org_id} do
      attrs = %{
        label: "A label",
        type: :quick_reply,
        interactive_content: %{},
        organization_id: org_id,
        language_id: language_fixture().id
      }

      assert {:ok, template} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      assert template.label == attrs[:label]
      assert template.type == :quick_reply
      assert template.interactive_content == %{}
      assert template.translations == %{}
      assert template.organization_id == org_id
      assert template.language_id == attrs[:language_id]
      assert template.send_with_title
    end

    test "valid interactive_template with optional fields", %{organization_id: org_id} do
      attrs = %{
        label: "A label",
        type: :quick_reply,
        interactive_content: %{},
        organization_id: org_id,
        language_id: language_fixture().id,
        translations: %{"a" => "b"},
        send_with_title: false
      }

      assert {:ok, template} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      refute template.send_with_title
      assert template.translations == %{"a" => "b"}
    end

    test "invalid interactive_template: missing required fields" do
      assert {:error, %Ecto.Changeset{valid?: false, required: required}} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, %{})
               |> Repo.insert()

      assert required == [:label, :type, :interactive_content, :organization_id, :language_id]
    end

    test "invalid interactive_template: label-type-organisation must be unique", %{
      organization_id: org_id
    } do
      label = "Some label"
      type = :quick_reply

      attrs = %{
        label: label,
        type: type,
        interactive_content: %{},
        organization_id: org_id,
        language_id: language_fixture().id
      }

      assert {:ok, _template} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, %{
                 label: label,
                 type: type,
                 interactive_content: %{a: 1},
                 organization_id: org_id,
                 language_id: language_fixture().id
               })
               |> Repo.insert()

      assert errors == [
               label:
                 {"has already been taken",
                  [
                    constraint: :unique,
                    constraint_name: "interactive_templates_label_type_organization_id_index"
                  ]}
             ]
    end

    test "invalid interactive_template: label-language-organisation must be unique", %{
      organization_id: org_id
    } do
      label = "Some label"
      language_id = language_fixture().id

      attrs = %{
        label: label,
        type: :quick_reply,
        interactive_content: %{},
        organization_id: org_id,
        language_id: language_id
      }

      assert {:ok, _template} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, %{
                 label: label,
                 type: :list,
                 interactive_content: %{a: 1},
                 organization_id: org_id,
                 language_id: language_id
               })
               |> Repo.insert()

      assert errors == [
               label:
                 {"has already been taken",
                  [
                    constraint: :unique,
                    constraint_name:
                      "interactive_templates_label_language_id_organization_id_index"
                  ]}
             ]
    end

    test "invalid interactive_template: organisation must exist" do
      attrs = %{
        label: "Some label",
        type: :quick_reply,
        interactive_content: %{},
        organization_id: 987_654,
        language_id: language_fixture().id
      }

      assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      assert errors == [
               organization_id:
                 {"does not exist",
                  [
                    constraint: :foreign,
                    constraint_name: "interactive_templates_organization_id_fkey"
                  ]}
             ]
    end

    test "invalid interactive_template: language must exist", %{organization_id: org_id} do
      attrs = %{
        label: "Some label",
        type: :quick_reply,
        interactive_content: %{},
        organization_id: org_id,
        language_id: 987_654
      }

      assert {:error, %Ecto.Changeset{valid?: false, errors: errors}} =
               InteractiveTemplate.changeset(%InteractiveTemplate{}, attrs)
               |> Repo.insert()

      assert errors == [
               language_id:
                 {"does not exist",
                  [
                    constraint: :foreign,
                    constraint_name: "interactive_templates_language_id_fkey"
                  ]}
             ]
    end
  end
end
