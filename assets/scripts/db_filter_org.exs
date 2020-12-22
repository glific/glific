defmodule Glific.Migrations do
  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Contacts.ContactsField,
    Contacts.Location,
    Extensions.Extension,
    Flows.Flow,
    Flows.FlowContext,
    Flows.FlowCount,
    Flows.FlowLabel,
    Flows.FlowResult,
    Flows.FlowRevision,
    Flows.WebhookLog,
    Groups.ContactGroup,
    Groups.Group,
    Groups.UserGroup,
    Jobs.BigqueryJob,
    Jobs.ChatbaseJob,
    Jobs.GcsJob,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Credential,
    Partners.Organization,
    Repo,
    Searches.SavedSearch,
    Templates.SessionTemplate,
    Tags.ContactTag,
    Tags.MessageTag,
    Tags.Tag,
    Tags.TemplateTag,
    Users.User
  }

  def execute do
    [shortcode] = System.argv()

    [organization_id] =
      Organization
      |> where([o], o.shortcode == ^shortcode)
      |> select([o], o.id)
      |> Repo.all(skip_organization_id: true)

    [
      BigqueryJob,
      ChatbaseJob,
      GcsJob,
      Extension,
      Credential,
      ContactsField,
      Location,
      Tag,
      TemplateTag,
      WebhookLog,
      FlowContext,
      FlowCount,
      FlowLabel,
      FlowResult,
      FlowRevision,
      Flow,
      MessageMedia,
      MessageTag,
      Message,
      ContactGroup,
      UserGroup,
      Group,
      ContactTag,
      SavedSearch,
      SessionTemplate,
      User,
      Contact
    ]
    |> Enum.each(fn module ->
      module
      |> where([q], q.organization_id != ^organization_id)
      |> Repo.delete_all(skip_organization_id: true)
    end)

    Organization
    |> where([q], q.organization_id != ^organization_id)
    |> Repo.delete_all(skip_organization_id: true)
  end
end

if Mix.env() in [:dev, :test] do
  Glific.Migrations.execute()
else
  IO.inspect "Can't run the script in production"
end
