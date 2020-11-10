# Flows

## Get All Flows

```graphql
query flows($filter: FlowFilter, $opts: Opts) {
  flows(filter: $filter, opts: $opts) {
    id
    uuid
    name
    versionNumber
    flowType
    keywords
  }
}

{
  "opts": {
    "limit": 2,
    "offset": 0,
    "order": "ASC"
  },
  "filter": {
    "name": "Workflow"
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
        "keywords": [
          "help",
          "मदद"
        ],
        "name": "Help Workflow",
        "uuid": "3fa22108-f464-41e5-81d9-d8a298854429",
        "versionNumber": "13.1.0"
      },
      {
        "flowType": "MESSAGE",
        "id": "2",
        "keywords": [
          "language"
        ],
        "name": "Language Workflow",
        "uuid": "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
        "versionNumber": "13.1.0"
      }
    ]
  }
}
```
This returns all the flows

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#flowfilter">FlowFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

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
        "name": "Help Workflow"
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
      keywords
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "keywords": [
      "tests",
      "testing"
    ],
    "name": "test workflow"
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
        "keywords": [
          "tests",
          "testing"
        ],
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
          "key": "name",
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
      keywords
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
    "name": "updated name",
    "keywords": ["test", "testing"]
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
        "name": "updated name",
        "keywords": [
          "test",
          "testing"
        ]
      }
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "updateFlow": {
      "errors": [
        {
          "key": "keywords",
          "message": "global keywords [test, testing] are already taken"
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

## Publish a Flow

```graphql
mutation publishFlow($uuid: UUID4!) {
  publishFlow(uuid: $uuid) {
    success
    errors {
      key
      message
    }
  }
}

{
  "uuid": "3fa22108-f464-41e5-81d9-d8a298854429"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "publishFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "publishFlow": {
      "errors": [
        {
          "key": "Flow UUID: 9a2788e1-26cd-44d0-8868-d8f0552a08a6",
          "message": "Resource not found"
        }
      ],
      "success": null
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
<a href="#publishflowresult">PublishFlowResult</a> | An error object or response true

## Start flow for a contact

```graphql
mutation startContactFlow($flowId: ID!, $contactId: ID!) {
  startContactFlow(flowId: $flowId, contactId: $contactId) {
  	success
  	errors {
    	key
  		message
  	}
  }
}

{
  "flowId": "1",
  "contactId": "2"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "startContactFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "startContactFlow": {
      "errors": [
        {
          "key": "contact",
          "message": "Cannot send the message to the contact."
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
flowId | <a href="#id">ID</a>! | required ||
contactId | <a href="#id">ID</a>! | required ||

### Return Parameters
Type | Description
--------- | ---- | ------- | -----------
<a href="#startflowresult">StartFlowResult</a> | An error object or success response true


## Start flow for a group contacts

```graphql
mutation startGroupFlow($flowId: ID!, $groupId: ID!) {
  startGroupFlow(flowId: $flowId, groupId: $groupId) {
  	success
  	errors {
    	key
  		message
  	}
  }
}

{
  "flowId": "1",
  "groupId": "1"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "startGroupFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "startGroupFlow": {
      "errors": [
        {
          "key": "Elixir.Glific.Flows.Flow 11",
          "message": "Resource not found"
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
flowId | <a href="#id">ID</a>! | required ||
groupId | <a href="#id">ID</a>! | required ||

### Return Parameters
Type | Description
--------- | ---- | ------- | -----------
<a href="#startflowresult">StartFlowResult</a> | An error object or success response true


## Copy a Flow

```graphql
mutation copyFlow($id: ID!, $input:FlowInput!) {
  copyFlow(id: $id, input: $input) {
    flow {
      id
      name
      keywords
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
    "name": "new name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "copyFlow": {
      "errors": null,
      "flow": {
        "id": "32",
        "keywords": [],
        "name": "new name"
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
<a href="#flowresult">FlowResult</a> | The copied flow object


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
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#uuid4">UUID4</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>versionNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ignoreKeywords</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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

### PublishFlowResult

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
<td colspan="2" valign="top"><strong>success</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

### StartFlowResult

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
<td colspan="2" valign="top"><strong>success</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ignoreKeywords</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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
  <td colspan="2" valign="top"><strong>name</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the flow name</td>
</tr>
<tr>
  <td colspan="2" valign="top"><strong>keyword</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the flow keyword</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#uuid4">UUID4</a></td>
<td></td>
</tr>
<tr>
  <td colspan="2" valign="top"><strong>status</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the status of flow revision draft/archived/done</td>
</tr>
</tbody>
</table>
