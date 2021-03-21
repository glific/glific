---
title: API Reference

language_tabs: # must be one of https://git.io/vQNgJ
  - shell
  - graphql
  - javascript

toc_footers:
  - <a href='https://glific.io/'>Glific</a>

includes:
  - webhook
  - auth
  - languages
  - providers
  - organizations
  - users
  - contacts
  - tags
  - contact_tag
  - messages_tags
  - search
  - saved_searches
  - messages
  - messages_media
  - session_templates
  - groups
  - contact_group
  - message_group
  - user_group
  - flows
  - import
  - types
  - scalars
  - enums
  - errors

search: true

code_clipboard: true
---

# Introduction

Welcome to the Glific API! You can use this API to access the Glific  endpoint via GraphQL. This is the
interface used between the Glific FrontEnd and BackEnd and as such is expected to be complete, documented
and tested.

We have language bindings in GraphQL and shell (for authentication).
You can view code examples in the dark area to the right.

## API Endpoint

For NGOs who already have an account with Glific, your API endpoint is "api." concatenated with
your current url. Thus if your Glific URL is: https://ilp.tides.coloredcow.com/, your API endpoint will
be: https://api.ilp.tides.coloredcow.com/api

Note that for authentication we use REST, and for the rest of the API we use [GraphQL](https://graphql.org).
We have also implemented [GraphQL subscriptions](https://graphql.org/blog/subscriptions-in-graphql-and-relay/)
if you want to be informed when we receive a message and other events.
