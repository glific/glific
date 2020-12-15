alias Glific.Repo
alias Glific.{Settings.Language, Tags.Tag, Search.Full}

import Ecto.Query

Glific.Repo.put_organization_id(1)
Glific.Repo.put_current_user(Glific.Users.get_user!(1))
