# Search

## Search Contacts and Conversations

```graphql
query search($term: String!, $searchFilter: SearchFilter!,
  $shouldSave: Boolean, $saveSearchLabel: String, $saveSearchShortcode: String,
  $contactOpts: Opts!, $messageOpts: Opts!) {

  search(term: $term, filter: $searchFilter,
    saveSearch: $shouldSave, saveSearchLabel: $saveSearchLabel, saveSearchShortcode: $saveSearchShortcode,
    contactOpts: $contactOpts, messageOpts: $messageOpts) {

    messages {
      id,
      body,
      tags{
        label
      }
    }

    contact {
      name
    }
  }
}

{
  "term": "def",
  "shouldSave": true,
  "saveSearchLabel": "Save with this name",
  "saveSearchShortcode": "SaveName",
  "searchFilter": {
    "includeTags": ["17"]
  },
  "messageOpts": {
    "limit": 3,
    "order": "ASC"
  },
  "contactOpts": {
    "order": "DESC",
    "limit": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
     "search": [
      {
        "contact": {
          "name": "Default receiver"
        },
        "messages": [
          {
            "body": "Architecto est soluta non dignissimos.",
            "id": "4",
            "tags": []
          },
          {
            "body": "ZZZ message body for order test",
            "id": "2",
            "tags": [
              {
                "label": "Compliment"
              },
              {
                "label": "Good Bye"
              },
              {
                "label": "Greeting"
              },
              {
                "label": "Thank You"
              }
            ]
          },
          {
            "body": "Omnis architecto qui pariatur autem minima.",
            "id": "3",
            "tags": []
          },
        ]
      }
    ]
  }
}
```
This returns a list of conversations that match the term and filters <a href="#conversation">Conversation</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
term | <a href="#string">String</a> | nil | keyword for search
filter | <a href="#searchfilter">SearchFilter</a> | nil | filter the list
saveSearch | <a href="#boolean">Boolean</a> | nil | Search should be saved or not
saveSearchLabel | <a href="#string">String</a> | nil | label for save search object
saveSearchShortcode | <a href="#string">String</a> | nil | shortcode for save search object
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset message options
contactOpts | <a href="#opts">Opts</a> | nil | limit / offset contact options

## Saved Search Execution

Runs a search as specified by a saved search. Can optionally send in a string to replace the saved search input string.

```graphql
query savedSearchExecute($id: ID!,$term:String) {
  savedSearchExecute(id: $id, term: $term) {
    contact {
      id
      name
    }
    messages {
      id
      body
    }
  }
}

{
  "id": 4
}
```

> The above query executes saved search 4 and returns JSON structured like this:

```json
{
  "data": {
    "savedSearchExecute": [
      {
        "contact": {
          "id": "2",
          "name": "Default receiver"
        },
        "messages": [
          {
            "body": "hindi",
            "id": "5"
          },
          {
            "body": "hola",
            "id": "7"
          }
        ]
      }
    ]
  }
}
```

This returns a list of conversations that match the term and saved search filter <a href="#conversation">Conversation</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required | Saved search ID
term | <a href="#string">String</a> | nil | optional keyword to add to saved search

## Saved Search Count

Returns the total number of contacts that match a saved search

```graphql
query savedSearchCount($id: ID!, $term: String) {
  savedSearchCount(id: $id, term: $term)
}


{
  "id": 4
}
```

```json
{
  "data": {
    "savedSearchCount": 2
  }
}
```

Returns a count of the number of contacts returned when executing the saved search.

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required | Saved search ID
term | <a href="#string">String</a> | nil | optional keyword to add to saved search

## Search Objects

### SearchFilter

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
<td colspan="2" valign="top"><strong>IncludeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ExcludeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td></td>
</tr>

</tbody>
</table>
