# Search

## Search Contacts and Conversations

```graphql
query search(  $saveSearchInput: SaveSearchInput,
  $searchFilter: SearchFilter!, $contactOpts: Opts!, $messageOpts: Opts!) {

  search(filter: $searchFilter, saveSearchInput: $saveSearchInput, contactOpts: $contactOpts, messageOpts: $messageOpts) {

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
  "saveSearchInput": {
      "label": "Save with this name",
      "shortcode": "SaveName"
  },

  "searchFilter": {
    "includeTags": ["17"],
    "includeGroups": ["1"],
    "includeUsers": ["1"],
    "term": "def",
    "dateRange": {
      "to": "2020-08-10",
      "from": "2020-08-12"
    }
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
filter | <a href="#searchfilter">SearchFilter</a> | nil | filter the list
saveSearchInput | <a href="#savesearchinput">SaveSearchInput</a> | nil | filter the list. The label and other parameter should be available.
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset message options
contactOpts | <a href="#opts">Opts</a> | nil | limit / offset contact options


## Search for a multiple section based on term

```graphql
query searchMulti( $searchFilter: SearchFilter!, $contactOpts: Opts!, $messageOpts: Opts!) {

  searchMulti(filter: $searchFilter, contactOpts: $contactOpts, messageOpts: $messageOpts) {
    contacts {
        body
        contact {
            name
        }
      }
      messages {
        body
        contact {
            name
        }
      }

      tags {
        body
        contact {
            name
        }

        tag {
          label
        }
      }
  }
}

{
  "searchFilter": {
    "term": "def"
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
     "searchMulti": [
      {
        "contacts": {
          {
            "body": "Architecto est soluta non dignissimos.",
            "contact": {
              "name": "Default receiver"
            }
          }
        },
        "messages": [
          {
            "body": "Architecto est defulat non dignissimos.",
            "contact": {
              "name": "Some contact name"
            }
          }
        ],

        "tags": [
          {
            "body": "Architecto est  non dignissimos.",
            "contact": {
              "name": "Any contact name"
            },
            "tag": {
              "label": "default tag"
            }
          }
        ]
      }
    ]
  }
}
```
This returns a list of messages filtered in 3 sections <a href="#searchmulti">SearchMulti</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#searchfilter">SearchFilter</a> | nil | filter the list
messageOpts | <a href="#opts">Opts</a> | nil | limit / offset message options
contactOpts | <a href="#opts">Opts</a> | nil | limit / offset contact options

## Saved Search Execution

Runs a search as specified by a saved search. Can optionally send in a string to replace the saved search input string.

```graphql
query search(
  $searchFilter: SearchFilter!, $contactOpts: Opts!, $messageOpts: Opts!) {

  search(filter: $searchFilter, contactOpts: $contactOpts, messageOpts: $messageOpts) {

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
  "searchFilter": {
    "savedSearchID": "17",
    "term": "def",
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
<td colspan="2" valign="top"><strong>Term</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>IncludeTags</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td></td>
</tr>


<tr>
<td colspan="2" valign="top"><strong>IncludeGroups</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>SearchGroup</strong></td>
<td valign="top">[<a href="#boolean">Boolean</a>]</td>
<td>When enabled, we retrieve messages sent to a group. IncludeGroups is the only filter used in this case.</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>IncludeUsers</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>DateRange</strong></td>
<td valign="top">[<a href="#daterange">DateRange</a>]</td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>SaveSearchID</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

</tbody>
</table>


### SaveSearchInput

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
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

</tbody>
</table>



### daterange

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
<td colspan="2" valign="top"><strong>From</strong></td>
<td valign="top"><a href="#date">Date (Y-M-d)</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>to</strong></td>
<td valign="top"><a href="#date">Date(Y-M-d)</a></td>
<td></td>
</tr>

</tbody>
</table>


### searchmulti

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
<td colspan="2" valign="top"><strong>Contacts</strong></td>
<td valign="top"><a href="#message">[<a id="message">Message</a>]</a></td>
<td>A list of messages filtered by message's contact name and phone</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Messages</strong></td>
<td valign="top"><a href="#message">[<a id="message">Message</a>]</a></td>
<td>A list of messages filtered by message's body</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Tags</strong></td>
<td valign="top"><a href="#message">[<a id="message">Message</a>]</a></td>
<td>A list of messages filtered by message's tag label and shortcode</td>
</tr>

</tbody>
</table>
