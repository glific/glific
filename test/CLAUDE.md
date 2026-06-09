# `test/` — Testing Conventions

Tests mirror `lib/` exactly: `lib/glific/widgets.ex` → `test/glific/widgets_test.exs`;
`lib/glific_web/schema/widget_types.ex` → `test/glific_web/schema/widget_test.exs`. Glific uses
plain ExUnit + custom case templates + a single `Fixtures` module (no ExMachina). External HTTP
is mocked with `Tesla.Mock` / ExVCR.

> Read this before writing or fixing tests. Coverage is gated in CI (Codecov), so new code needs
> tests, not just a green compile.

## Pick the right case template

| Case | `use` | For | Setup it gives you |
|------|-------|-----|--------------------|
| `Glific.DataCase` | business logic / DB | contexts, schemas, workers | SQL sandbox; `Repo.put_organization_id(1)`; a `manager` current_user; org-1 cache filled. Yields `%{organization_id: 1}`. |
| `GlificWeb.ConnCase` | GraphQL / HTTP | schema + resolver tests | all of the above **plus** `staff`/`manager`/`user` in context, BSP tokens, and the `auth_query_gql_by/3` macro. |
| `GlificWeb.ChannelCase` | Phoenix channels | WebSocket subscriptions | channel test harness |

- Default org in every test is `organization_id: 1`.
- `use Glific.DataCase, async: true` enables parallel runs — only when the test touches **no**
  shared global state (caches, FunWithFlags, Tesla.Mock globals, ETS). When unsure, leave it sync.
- Seed reference data in `setup` with `Glific.Seeds.SeedsDev.seed_*` (e.g. `seed_tag()`,
  `seed_language()`) — many tests assume seeded languages/tags exist.

## DataCase test shape (mirror `test/glific/tags_test.exs`)

```elixir
defmodule Glific.WidgetsTest do
  use Glific.DataCase
  alias Glific.{Fixtures, Widgets, Widgets.Widget}

  describe "widgets" do
    @valid_attrs   %{name: "some name", ...}
    @update_attrs  %{name: "updated", ...}
    @invalid_attrs %{name: nil, organization_id: 1}

    test "list_widgets/1 returns all widgets", %{organization_id: _} = attrs do
      widget = Fixtures.widget_fixture(attrs)
      assert Widgets.list_widgets(%{filter: attrs}) |> Enum.any?(&(&1.id == widget.id))
    end

    test "create_widget/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Widgets.create_widget(@invalid_attrs)
    end
  end
end
```

Cover, per entity: list, count, get!/fetch (found + not-found), create (valid + invalid),
update (valid + invalid), delete, and any custom filters/validations. Use `errors_on(changeset)`
(provided by `DataCase`) to assert on validation messages.

## GraphQL test shape (mirror `test/glific_web/schema/tag_test.exs`)

```elixir
defmodule GlificWeb.Schema.WidgetTest do
  use GlificWeb.ConnCase
  use Wormwood.GQLCase
  alias Glific.{Fixtures, Seeds.SeedsDev}

  setup do
    SeedsDev.seed_widget()      # if reference data is needed
    :ok
  end

  load_gql(:list,   GlificWeb.Schema, "assets/gql/widgets/list.gql")
  load_gql(:create, GlificWeb.Schema, "assets/gql/widgets/create.gql")
  # ... by_id, count, update, delete ...

  test "create a widget", %{manager: user} do
    result = auth_query_gql_by(:create, user, variables: %{"input" => %{"name" => "x"}})
    assert {:ok, query_data} = result
    assert "x" == get_in(query_data, [:data, "createWidget", "widget", "name"])
  end
end
```

- `auth_query_gql_by(:op, user, variables: %{...})` runs the loaded op as `user`. The
  `%{staff: ..., manager: ...}` users come from `ConnCase` setup — pick the role that matches the
  field's `Authorize` level, and **add a test asserting an under-privileged role is rejected**
  (`get_in(query_data, [:errors])` / `"Unauthorized"`).
- Read results with `get_in(query_data, [:data, "<camelCaseField>", ...])`. GraphQL keys are
  camelCase strings; Ecto fields are snake_case atoms.
- Every loaded op needs its `.gql` file under `assets/gql/<entity>/` (see `lib/glific_web/CLAUDE.md`).

## Fixtures

- Live in `test/support/fixtures.ex` as `entity_fixture(attrs \\ %{})` with Faker-based defaults;
  nested deps are created automatically (e.g. `organization_fixture` makes a contact first).
- **Add a `widget_fixture/1` to `Fixtures` for any new entity** and reuse it everywhere — don't
  hand-roll inserts in individual tests.
- More complex setups live under `test/support/fixtures/`.

## External services — never hit the network

- HTTP: `Tesla.Mock.mock(fn %{method: :post, url: url} -> %Tesla.Env{status: 200, body: ...} end)`.
- Replayed cassettes: ExVCR fixtures under `test/support/ex_vcr`.
- BSP (Gupshup/Maytapi), BigQuery, GCS, Dialogflow, Gemini, OpenAI calls **must** be mocked.
  A test that makes a real outbound call is a bug.

## Running & coverage

```bash
mix test                              # create/migrate test DB, run all
mix test path/to/file_test.exs:NN     # single test by line
mix test_full                         # full DB drop+reload+migrate, then test (CI parity)
mix coveralls.html                    # local coverage report
```

CI runs tests and enforces Codecov thresholds. Flaky tests are usually ordering or
shared-global-state issues — prefer deterministic ordering (`order_by`) and avoid `async: true`
when touching caches/flags. See the `fix-flaky-tests` and `improve-code-coverage` skills.
