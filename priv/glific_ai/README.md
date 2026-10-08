# Glific AI documentation corpus

The documents Glific AI searches when someone asks how the product works.
`Glific.AI.Documentation` splits them on their markdown headings and keeps the
index in `:persistent_term`; `search_documentation` is the tool that reaches
them.

## What is here

| File | Covers | Source |
|------|--------|--------|
| `glific_platform_guide.md` | Screens, navigation and step-by-step guides | Written from the public docs at <https://glific.github.io/docs/> |
| `glific_operations_manual.md` | How the platform behaves — flows, triggers, sending, limits | Written from the codebase and the public docs |
| `glific_chatbot_knowledge_base.md` | Question-and-answer companion, one self-contained answer per section | Written from the public docs, restructured for retrieval |
| `glific_diagnose_playbook.md` | What to check when something is reported broken, and what each field means | Written against the Glific AI read tools |

## Rules for editing

**Headings carry four times the weight of body text**, and they are what a
complaint has to match. Write them in the words people use — "my flow is not
running", not "flow lifecycle troubleshooting". A section nobody's phrasing
reaches is a section that will never be returned.

**One answer per section.** A section is returned on its own, without the text
around it, so it has to stand alone. A heading with nothing under it is dropped
from the index.

**Keep a `📖 Source:` line** near the top of a page or section where one
exists. It becomes the `url` on every section beneath it, which is how an
answer cites a page.

**Do not add file or line references.** They are stripped at index time
(`strip_source_refs/1`), because an NGO asking how to publish a flow should
never be handed an Elixir line number. If you need provenance for a fact,
put it in a comment in the pull request, not in the document.

**Bodies are capped at 1,500 bytes** when returned. A section longer than that
is cut and marked `truncated`, so put the answer first and the elaboration
after.

## Adding a document

Add the file here **and** add it to `@documents` in
`lib/glific/ai/documentation.ex`. The index is built from that list rather than
from whatever is in this directory, so that a developer's local copy and what
ships are the same thing.

## Staleness

These are a snapshot, not a live mirror of <https://glific.github.io/docs/>.
Nothing detects drift automatically. When a feature changes in a way that
changes the answer — a renamed screen, a new limit, a changed default — the
corresponding section has to be edited by hand in the same pull request.

Two checks worth running after any edit:

```
mix test test/glific/ai/documentation_test.exs
```

covers the corpus — every subject still returns something, no body exceeds the
cap, complaints still reach the playbook.

```
mix test test/glific/ai/documentation_ranking_test.exs
```

covers the ranker against a fixture corpus, not these documents, so it should
be unaffected by anything written here. If it breaks after a documentation
edit, something is wrong with the change rather than with the text.
