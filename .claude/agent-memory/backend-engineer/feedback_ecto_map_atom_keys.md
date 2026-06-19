---
name: feedback-ecto-map-atom-keys
description: Ecto :map (JSONB) fields preserve atom keys in the struct returned by Repo.insert — NOT string keys
metadata:
  type: feedback
---

When a `:map` field is inserted with an atom-keyed Elixir map (e.g. `%{name: "x"}`), `Repo.insert/1` returns a struct where the map field STILL has atom keys — `%{name: "x"}`, NOT `%{"name" => "x"}`.

**Why:** Ecto's RETURNING clause for `Repo.insert` only returns the `id` column (not the full row for `:map` fields in the same way as scalars). The in-memory changeset's atom-keyed map is used for the returned struct. Only subsequent `Repo.get` / `Repo.fetch_by` calls round-trip through JSON and return string keys.

**How to apply:** In tests, assert `record.map_field[:atom_key]` (not `record.map_field["string_key"]`) when the struct comes directly from `Repo.insert`. Use `Repo.get/2` to get the DB-round-tripped version with string keys.

Related: [[project-prompt-generator-m1]]
