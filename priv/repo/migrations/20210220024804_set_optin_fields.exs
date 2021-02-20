defmodule Glific.Repo.Migrations.SetOptinFields do
  use Ecto.Migration

  import Ecto.Query

  alias Glific.{Contacts.Contact, Repo}
  def change do
    migrate_optin_data()
  end


  defp migrate_optin_data() do
    # Set false status for contacts not opted in
    Contact
    |> where([c], is_nil(c.optin_time))
    |> update([c], set: [optin_status: false])
    |> Repo.update_all([], skip_organization_id: true)

    # Set true status where we have an option_date,
    # also set method as URL since they opted in via Gupshup
    Contact
    |> where([c], not is_nil(c.optin_time))
    |> update([c], set: [optin_status: true, optin_method: "URL"])
    |> Repo.update_all([], skip_organization_id: true)
  end
end
