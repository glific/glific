defmodule Glific.Migrations do
  import Ecto.Query

  alias Glific.{
    Contacts.Contact,
    Flows.FlowResult,
    Messages.Message,
    Messages.MessageMedia,
    Partners.Credential,
    Repo,
    Users.User
  }

  def execute do
    # mask phone number and update password to secret1234
    from([u] in User,
      update: [
        set: [
          phone: u.id,
          password_hash:
            "$pbkdf2-sha512$100000$YR5Kal/tvyaNQnUFN6xCBg==$65gUuqF3xn4QhB1sSTH4qIQRepJ2FM1OEoqC/40Z8/ZFdSRSrTunBdpdOUCB/tpbvi3i0qJUe+ftVqB91NjbrQ=="
        ]
      ]
    )
    |> Repo.update_all([], skip_organization_id: true)

    # mask phone number and reset fields
    from([c] in Contact,
      update: [set: [phone: c.id, fields: nil]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    # sha256 message body
    # using scape format to avoid error
    from([m] in Message,
      update: [set: [body: fragment("sha256(decode(?, 'escape'))", m.body)]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    # sha256 urls
    from([m] in MessageMedia,
      update: [
        set: [
          url: fragment("sha256(decode(?, 'escape'))", m.url),
          source_url: fragment("sha256(decode(?, 'escape'))", m.source_url),
          thumbnail: fragment("sha256(decode(?, 'escape'))", m.thumbnail)
        ]
      ]
    )
    |> Repo.update_all([], skip_organization_id: true)

    # reset flow results
    from([f] in FlowResult,
      update: [set: [results: nil]]
    )
    |> Repo.update_all([], skip_organization_id: true)

    # delete credentials
    from([f] in Credential,
      update: [set: [secrets: nil]]
    )
    |> Repo.update_all([], skip_organization_id: true)
  end
end

if Mix.env() in [:dev, :test] do
  Glific.Migrations.execute()
else
  IO.inspect "Can't run the script in production"
end
