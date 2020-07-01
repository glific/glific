# Search

## Search In conversation

```graphql
query search($term: String!, $shouldSave: Boolean!, $searchLabel: String!, $searchFilter: SearchFilter!) {
  search(term: $term, saveSearch: $shouldSave, saveSearchLabel: $saveSearchLabel, filter: $searchFilter) {
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
  "searchFilter": {
    "includeTags": ["17"]
  },
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
This returns all the full text for the organization filtered by the input <a href="#conversation">Conversation</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
term | <a href="#sting">String</a> | nil | keyword for search
filter | <a href="#searchfilter">SearchFilter</a> | nil | filter the list
saveSearch | <a href="#boolean">Boolean</a> | nil | Search should be saved or not
saveSearchLabel | <a href="#string">String</a> | nil | label for save search object
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset message options
contactOpts | <a href="#opts">Opts</a> | nil | limit / offset contact options


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
