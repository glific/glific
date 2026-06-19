---
name: feedback-credo-with-redundant-clause
description: Credo strict flags redundant last `with` clause when body just returns the matched value
metadata:
  type: feedback
---

Credo (strict mode) flags: "Last clause in `with` is redundant" when the final `<-` pattern just binds a value and the `do` block returns it unchanged.

**Why:** It's simpler and more idiomatic to put the last call directly in the `do` body.

**How to apply:**

Instead of:
```elixir
with {:ok, foo} <- step_one(),
     {:ok, result} <- step_two(foo) do
  {:ok, result}
end
```

Write:
```elixir
with {:ok, foo} <- step_one() do
  step_two(foo)
end
```
