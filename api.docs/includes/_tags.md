# Tags

## Get All Tags

```graphql
query tags($filter: TagFilter, $opts: Opts) {
  tags(filter: $filter, opts:$opts) {
    id
    label
    language {
      id
      label
    }
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "languageId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "tags": [
      {
        "id": "18",
        "label": "Child",
        "language": {
          "id": "2",
          "label": "English (United States)"
        }
      },
      {
        "id": "3",
        "label": "Compliment",
        "language": {
          "id": "2",
          "label": "English (United States)"
        }
      },
      {
        "id": "2",
        "label": "Contacts",
        "language": {
          "id": "2",
          "label": "English (United States)"
        }
      }
    ]
  }
}
```
This returns all the tags for the organization filtered by the input <a href="#tagfilter">TagFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#tagfilter">TagFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Get a specific Tag by ID

```graphql
query tag($id: ID!) {
  tag(id: $id) {
    tag {
      id
      label
      language {
        id
        label
      }
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
    "tag": {
      "tag": {
        "id": "2",
        "label": "Contacts",
        "language": {
          "id": "2",
          "label": "English (United States)"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a> | nil ||

## Count all Tags

```graphql
query countTags($filter: TagFilter) {
  countTags(filter: $filter)
}

{
  "filter": {
    "languageId": 2
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countTags": 22
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#tagfilter">TagFilter</a> | nil | filter the list

## Create a Tag

```graphql
mutation createTag($input:TagInput!) {
  createTag(input: $input) {
    tag {
      id
      label
      language {
        id
        label
      }
      description
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "label": "This is a new tag for this example",
    "description": "This is a cool description",
    "languageId": "1"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createTag": {
      "errors": null,
      "tag": {
        "description": "This is a cool description",
        "id": "26",
        "label": "This is a new tag for this example",
        "language": {
          "id": "1",
          "label": "Hindi"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#taginput">TagInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#tagresult">TagResult</a> | The created tag object

## Update a Tag

```graphql
mutation updateTag($id: ID!, $input:TagInput!) {
  updateTag(id: $id, input: $input) {
    tag {
      id
      label
      language {
        id
        label
      }
      description
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
    "label": "This is a update tag for this example",
    "description": "This is a updated cool description",
    "languageId": "2"
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateTag": {
      "errors": null,
      "tag": {
        "description": "This is a updated cool description",
        "id": "26",
        "label": "This is a update tag for this example",
        "language": {
          "id": "2",
          "label": "English (United States)"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#taginput">TagInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#tagresult">TagResult</a> | The updated tag object


## Delete a Tag

```graphql
mutation deleteTag($id: ID!) {
  deleteTag(id: $id) {
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
    "deleteTag": {
      "errors": null,
      "tag": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteTag": {
      "errors": [
        {
          "key": "Elixir.Glific.Tags.Tag 29",
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
<a href="#tagresult">TagResult</a> | An error object or empty

## Tag Objects

### Tag

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
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parent</strong></td>
<td valign="top"><a href="#tag">Tag</a></td>
<td></td>
</tr>
</tbody>
</table>

### TagResult ###

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
<td colspan="2" valign="top"><strong>tag</strong></td>
<td valign="top"><a href="#tag">Tag</a></td>
<td></td>
</tr>
</tbody>
</table>

## Tag Inputs ##


### TagFilter ###

Filtering options for tags

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
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the description

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>

Match the active flag

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>

Match the reserved flag

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the label

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match a language

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>languageId</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td>

Match a language id

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parent</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the parent

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parentId</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td>

Match the parent

</td>
</tr>
</tbody>
</table>

### TagInput ###

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
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>languageId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>
