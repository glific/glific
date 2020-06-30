# Conversations

## Get All Conversations

```graphql
query conversations($filter: ConversationsFilter, $contactOpts: Opts, $messageOpts: Opts) {
  conversations(filter: $filter, contactOpts:$contactOpts, messageOpts: $messageOpts) {
    contact {
      id
      name
      phone
    }
    messages {
      id
      body
      flow
      type
    }
  }
}

{
  "messageOpts": {
    "limit": 1,
    "order": "ASC"
  },
  "contactOpts": {
    "order": "DESC",
    "limit": 2
  },
  "filter": {
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "conversations": [
      {
        "contact": {
          "id": "194",
          "name": "Rossie Bruen",
          "phone": "657/719-5377"
        },
        "messages": [
          {
            "body": "There is nothing either good or bad, but thinking makes it so.",
            "flow": "INBOUND",
            "id": "8576",
            "type": "TEXT"
          }
        ]
      },
      {
        "contact": {
          "id": "36",
          "name": "Althea Hirthe",
          "phone": "542-462-6684"
        },
        "messages": [
          {
            "body": "Now is the winter of our discontent.",
            "flow": "OUTBOUND",
            "id": "2297",
            "type": "TEXT"
          }
        ]
      }
    ]
  }
}
```

This returns all the conversations starting with most recent. You can use limit, offset and
sort order options on both the contacts and the conversations returned

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#conversationfilter">ConversationFilter</a> | nil | filter the conversations
contactOpts | <a href="#opts">Opts</a> | nil | limit / offset / sort order contact options
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset / sort order message options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#conversation">Conversation</a>] | A list of conversation objects

## Get a specific Conversation by Contact ID

```graphql
query conversation($filter: ConversationFilter, $contactId: Gid!, $messageOpts: Opts) {
  conversation(filter: $filter, contactId: $contactId, messageOpts: $messageOpts) {
    contact {
      id
      name
      phone
    }
    messages {
      id
      body
      flow
      type
    }
  }
}

{
  "messageOpts": {
    "limit": 3,
    "order": "ASC"
  },
  "contactId":"194",
  "filter": {
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "conversation": {
      "contact": {
        "id": "194",
        "name": "Rossie Bruen",
        "phone": "657/719-5377"
      },
      "messages": [
        {
          "body": "There is nothing either good or bad, but thinking makes it so.",
          "flow": "INBOUND",
          "id": "8576",
          "type": "TEXT"
        },
        {
          "body": "Rich gifts wax poor when givers prove unkind.",
          "flow": "OUTBOUND",
          "id": "8575",
          "type": "TEXT"
        },
        {
          "body": "What's in a name? That which we call a rose by any other name would smell as sweet.",
          "flow": "INBOUND",
          "id": "8574",
          "type": "TEXT"
        }
      ]
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#conversationfilter">ConversationFilter</a> | nil | filter the conversation
contactId | <a href="#id">ID</a> | nil ||
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset / sort order message options

### Return Parameters
Type | Description
| ---- | -----------
<a href="#conversation">Conversation</a> | The conversation object

## Conversation Objects

### Conversation

<table>
<thead>
<tr>
<th align="left">Field</th>
<th align="right">Argument</th>
<th align="left">Type</th>
<th align="left">Description</th>
</tr>
</thead>
<tbody>
<tr>
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>messages</strong></td>
<td valign="top">[<a href="#message">Message</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### ConversationFilter

Filtering options for conversations

<table>
<thead>
<tr>
<th colspan="2" align="left">Field</th>
<th align="left">Type</th>
<th align="left">Description</th>
</tr>
</thead>
<tbody>
<tr>
<td colspan="2" valign="top"><strong>excludeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Exclude conversations with these tags

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>includeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Include conversations with these tags

</td>
</tr>
</tbody>
</table>

### ConversationsFilter

Filtering options for conversations

<table>
<thead>
<tr>
<th colspan="2" align="left">Field</th>
<th align="left">Type</th>
<th align="left">Description</th>
</tr>
</thead>
<tbody>
<tr>
<td colspan="2" valign="top"><strong>excludeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Exclude conversations with these tags

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#gid">Gid</a></td>
<td>

Match one contact ID

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ids</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Match multiple contact ids

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>includeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Include conversations with these tags

</td>
</tr>
</tbody>
</table>
