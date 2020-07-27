# Flows

## Get All Flows

```graphql
query flows {
  flows {
    id
    uuid
    name
    shortcode
    versionNumber
    flowType
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "flows": [
      {
        "flowType": "MESSAGE",
        "id": "1",
        "name": "Help Workflow",
        "shortcode": "help",
        "uuid": "3fa22108-f464-41e5-81d9-d8a298854429",
        "versionNumber": "13.1.0"
      },
      {
        "flowType": "MESSAGE",
        "id": "2",
        "name": "Language Workflow",
        "shortcode": "language",
        "uuid": "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
        "versionNumber": "13.1.0"
      }
    ]
  }
}
```
This returns all the flows

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#flow">Flow</a>] | List of flows

## Get a specific Flow by ID

```graphql
query flow($id: ID!) {
  flow(id: $id) {
    flow {
      id
      name
      shortcode
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
    "flow": {
      "flow": {
        "id": "1",
        "name": "Help Workflow",
        "shortcode": "help"
      }
    }
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
<a href="#flowresult">FlowResult</a> | Queried Flow


## Count all Flows

```graphql
query countFlows($filter: FlowFilter) {
  countFlows(filter: $filter)
}

{
  "filter": {
    "name": "help"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countFlows": 2
  }
}
```


## Create a Flow

```graphql
mutation ($input: FlowInput!) {
  createFlow(input: $input) {
    flow {
      id
      name
      shortcode
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "name": "test workflow",
    "shortcode": "test"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createFlow": {
      "errors": null,
      "flow": {
        "id": "12",
        "name": "test workflow"
      }
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "createFlow": {
      "errors": [
        {
          "key": "shortcode",
          "message": "can't be blank"
        }
      ],
      "flow": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#flowinput">FlowInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#flowresult">FlowResult</a> | The created flow object

## Update a Flow

```graphql
mutation updateFlow($id: ID!, $input:FlowInput!) {
  updateFlow(id: $id, input: $input) {
    flow {
      id
      name
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "1",
  "input": {
    "name": "updated name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateFlow": {
      "errors": null,
      "flow": {
        "id": "1",
        "name": "updated name"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#flowinput">FlowInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#flowresult">FlowResult</a> | The updated flow object


## Delete a Flow

```graphql
mutation deleteFlow($id: ID!) {
  deleteFlow(id: $id) {
    flow {
      id
      name
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "3"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteFlow": {
      "errors": null,
      "flow": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteFlow": {
      "errors": [
        {
          "key": "Elixir.Glific.Flows.Flow 3",
          "message": "Resource not found"
        }
      ],
      "flow": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||

### Return Parameters
Type | Description
--------- | ---- | ------- | -----------
<a href="#flowresult">FlowResult</a> | An error object or empty

## Flow Objects

### Flow

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
<td colspan="2" valign="top"><strong>flowType</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>versionNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### FlowResult

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
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
</tbody>
</table>


## Flow Inputs ##

### FlowInput

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
<td colspan="2" valign="top"><strong>name</strong></td>
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

### FlowFilter ###

Filtering options for flows

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
  <td colspan="2" valign="top"><strong>Name</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the flow name</td>
</tr>
</tbody>
</table>
