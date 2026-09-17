# Second Manual

A second fixture document. Two are needed because a tie that is broken by
filename only shows up when the tying sections come from different files.

## Ties

### Webhook timeout handling

Webhook timeout. This heading and body are chosen to tie with the short
section in the other document, so that ordering between them is decided by the
ranker rather than by which file was read first.

## Fences

### Section with a fenced comment

A `#` inside a fenced block is a comment in the language being shown, not a
markdown heading. Everything below the fence belongs to this section.

```bash
# This is a shell comment, not a heading
glific deploy --env production
```

The sentence after the fence is still part of this section, and the word
sentinelaardvark proves it: a search for that word must find this section and
not a section named after the comment.

## Short terms

### OTP and API and GCS

📖 Source: https://example.test/docs/short-terms/

Three-letter topics that a length guard would hide. The body deliberately
avoids repeating them so that only the heading carries the signal.
