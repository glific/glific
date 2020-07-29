# Message Media

## Get all message media

```graphql
query messagesMedia($opts: Opts) {
  messagesMedia(filter: $filter, opts:$opts) {
    id
    url
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "messagesMedia": [
      {
        "id": "3",
        "url": "http://robohash.org/set_set3/bgset_bg1/U0E0G",
      },
      {
        "id": "4",
        "url": "http://robohash.org/set_set1/bgset_bg1/dhac5",
      },
    ]
  }
}
```
This returns all the messages media for the organization.

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Get a specific Message Media by ID

```graphql
query messageMedia($id: ID!) {
  messageMedia(id: $id) {
    messageMedia {
      id
      url
    }
  }
}

{
  "id": 2
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "messageMedia": {
      "messageMedia": {
        "id": "2",
        "url": "http://robohash.org/set_set3/bgset_bg1/ClrvA"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a>

## Count all Message Media

```graphql
query countMessagesMedia {
  countMessagesMedia
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countMessagesMedia": 100
  }
}
```

## Create a Message Media

```graphql
mutation createMessageMedia($input:MessageMediaInput!) {
  createMessageMedia(input: $input) {
    messageMedia {
      id
      url
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "url": "http://robohash.org/set_set3/bgset_bg1/ClrvA",
    "source_url": "http://robohash.org/set_set3/bgset_bg1/ClrvA"
    "caption": "This is a caption"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "messageMedia": {
      "errors": null,
      "messageMedia": {
        "id": "26",
        "url": "http://robohash.org/set_set3/bgset_bg1/ClrvA"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messagemediainput">MessageMediaInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#message_media_result">MessageMediaResult</a> | The created message media object

## Update a Message Media

```graphql
mutation updateMessageMedia($id: ID!, $input:MessageMediaInput!) {
  updateMessageMedia(id: $id, input: $input) {
    messageMedia {
      id
      url
      caption 
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "26",
  "input": {
    "url": "http://robohash.org/set_set1/bgset_bg1/b7FBMrsOQbn8EJ",
    "caption": "This is a caption"
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateMessageMedia": {
      "errors": null,
      "messageMedia": {
        "id": "26",
        "url": "http://robohash.org/set_set1/bgset_bg1/b7FBMrsOQbn8EJ",
        "caption": "This is a caption"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#messagemediainput">MessageMediaInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#messagemediaresult">MessageMediaResult</a> | The updated message media object


## Delete a Message Media

```graphql
mutation deleteMessageMedia($id: ID!) {
  deleteMessageMedia(id: $id) {
    errors {
      key
      message
    }
  }
}

{
  "id": "26"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteMessageMedia": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteMessageMedia": {
      "errors": [
        {
          "key": "Elixir.Glific.Messages.MessageMedia 26",
          "message": "Resource not found"
        }
      ]
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||

### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messagemediaresult">MessageMediaResult</a> | An error object or empty


## Message Media Objects

### MessageMedia

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
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>source_url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>thumbnail</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>caption</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerMediaId</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

</tbody>
</table>

### MessageMediaResult ###

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
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>MessageMedia</strong></td>
<td valign="top"><a href="#messagemedia">MessageMedia</a></td>
<td></td>
</tr>
</tbody>
</table>

## Message Media Inputs ##

### MessageMediaInput ###

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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>source_url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>thumbnail</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>caption</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>


</tbody>
</table>
