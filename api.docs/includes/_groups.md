# Groups

## Get All Groups

```graphql
query groups($filter: GroupFilter, $opts: Opts) {
  groups(filter: $filter, opts:$opts) {
    id
    label
    isRestricted
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "label": "Group"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "groups": [
      {
        "id": "1",
        "isRestricted": false,
        "label": "My First Group"
      }
    ]
  }
}
```
This returns all the groups for the organization

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#groupfilter">GroupFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Get a Group by ID

```graphql
query group($id: ID!) {
  group(id: $id) {
    group {
      id
      label
      isRestricted
    }
  }
}

{
    "id": 1
}
```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "group": {
      "group": {
        "id": "1",
        "isRestricted": false,
        "label": "My First Group"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | nil |

## Create Group
```graphql
mutation createGroup($input: GroupInput!) {
  createGroup(input: $input) {
    group {
      id
      label
    }
    errors {
      key
      message
    }
  }
}
{
  "input": {
    "label": "My First Group"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createGroup": {
      "group": {
        "id": "1",
        "label": "My First Group"
      }
    }
  }
}

{
  "data": {
    "createGroup": {
      "errors": [
        {
          "key": "label",
          "message": "has already been taken"
        }
      ],
      "group": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#groupinput">GroupInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#groupresult">GroupResult</a> | The created group object

## Update a Group

```graphql
mutation updateGroup($id: ID!, $input: GroupInput!) {
  updateGroup(id: $id, input: $input) {
    group {
      id
      label
      isRestricted
    }
    errors {
      key
      message
    }
  }
}

{
  "id": 2,
    "input": {
    "label": "My First Updated non-Restricted Group",
    "isRestricted": false
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateGroup": {
      "errors": null,
      "group": {
        "id": "2",
        "isRestricted": false,
        "label": "My First Updated non-Restricted Group"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required |
input | <a href="#groupinput">GroupInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#groupresult">GroupResult</a> | The updated group object


## Delete a Group

```graphql
mutation deleteGroup($id: ID!) {
  deleteGroup(id: $id) {
    errors {
      key
      message
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
    "deleteGroup": {
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required |

### Return Parameters
Type | Description
| ---- | -----------
<a href="#groupresult">GroupResult</a> | An error object or empty


## Group Objects

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
<td colspan="2" valign="top"><strong>isRestricted</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tbody>
</table>

### GroupResult

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
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#group">Group</a></td>
<td></td>
</tr>
</tbody>
</table>

## Group Inputs

### GroupInput

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
<td colspan="2" valign="top"><strong>isRestricted</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>
