# Triggers

## Get All Triggers

```graphql
query triggers($filter: TriggerFilter) {
  triggers {
    days
    endDate
    flow {
      id
      name
    }
    group {
      id
      label
    }
    isActive
    isRepeating
    startAt
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "triggers": [
      {
        "__typename": "Trigger",
        "days": [1],
        "endDate": "2021-03-08",
        "flow": {
          "__typename": "Flow",
          "id": "1",
          "name": "Help Workflow"
        },
        "group": {
          "__typename": "Group",
          "id": "1",
          "label": "Optin contacts"
        },
        "isActive": true,
        "isRepeating": false,
        "startAt": "2021-03-08T08:22:51Z"
      },
      {
        "__typename": "Trigger",
        "days": [1],
        "endDate": "2021-03-08",
        "flow": {
          "__typename": "Flow",
          "id": "1",
          "name": "Help Workflow"
        },
        "group": {
          "__typename": "Group",
          "id": "1",
          "label": "Optin contacts"
        },
        "isActive": false,
        "isRepeating": false,
        "startAt": "2019-06-12T04:19:55Z"
      }
    ]
  }
}
```

This returns all the triggers for the organization filtered by the input <a href="#triggerfilter">TriggerFilter</a>

### Query Parameters

| Parameter | Type                                       | Default | Description                         |
| --------- | ------------------------------------------ | ------- | ----------------------------------- |
| filter    | <a href="#triggerfilter">TriggerFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                   | nil     | limit / offset / sort order options |

## Get a specific Trigger by ID

```graphql
query trigger($id: ID!) {
  trigger(id: $id) {
    trigger {
      days
      endDate
      flow {
        name
        id
        keywords
      }
      frequency
      group {
        id
        label
      }
      isActive
      isRepeating
    }
    errors {
      key
      message
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
    "trigger": {
      "errors": null,
      "trigger": {
        "__typename": "Trigger",
        "days": [1, 2],
        "endDate": "2021-03-08",
        "flow": {
          "__typename": "Flow",
          "id": "1",
          "keywords": ["help", "मदद"],
          "name": "Help Workflow"
        },
        "frequency": "",
        "group": {
          "__typename": "Group",
          "id": "1",
          "label": "Optin contacts"
        },
        "isActive": true,
        "isRepeating": false
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                 | Default | Description |
| --------- | -------------------- | ------- | ----------- |
| ID        | <a href="#id">ID</a> | nil     |             |

## Count all Triggers

```graphql
query countTriggers($filter: TriggerFilter) {
  countTriggers(filter: $filter)
}

{
  "filter": {
    "flowId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countTriggers": 1
  }
}
```

### Query Parameters

| Parameter | Type                                       | Default | Description     |
| --------- | ------------------------------------------ | ------- | --------------- |
| filter    | <a href="#triggerfilter">TriggerFilter</a> | nil     | filter the list |

## Create a Trigger

```graphql
mutation createTrigger($input: TriggerInput!) {
  createTrigger(input: $input) {
    trigger {
      days
      endDate
      flow {
        id
        name
      }
      frequency
      group {
        id
        label
      }
      isActive
      isRepeating
      startAt
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "days": 1,
    "flowId": 1,
    "groupId": 1,
    "startAt": "2020-12-30T13:15:19Z",
    "endDate": "2020-12-29T13:15:19Z",
    "isActive": false,
    "isRepeating": false
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createTrigger": {
      "__typename": "TriggerResult",
      "errors": null,
      "trigger": {
        "__typename": "Trigger",
        "days": [1],
        "endDate": "2021-03-08",
        "flow": {
          "__typename": "Flow",
          "id": "1",
          "name": "Help Workflow"
        },
        "frequency": "",
        "group": {
          "__typename": "Group",
          "id": "2",
          "label": "Optout contacts"
        },
        "isActive": false,
        "isRepeating": false,
        "startAt": "2021-03-08T08:22:51Z"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                                     | Default  | Description |
| --------- | ---------------------------------------- | -------- | ----------- |
| input     | <a href="#triggerinput">TriggerInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#triggerresult">TriggerResult</a> | The created trigger object |

## Update a Trigger

```graphql
mutation updateTrigger($id: ID!, $input: TriggerUpdateInput!) {
  updateTrigger(id: $id, input: $input) {
    trigger {
      days
      endDate
      flow {
        id
        name
      }
      frequency
      group {
        id
        label
      }
      isRepeating
      startAt
      isActive
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
    "flowId": 2,
    "isRepeating": false
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateTrigger": {
      "__typename": "TriggerResult",
      "errors": null,
      "trigger": {
        "__typename": "Trigger",
        "days": [1],
        "endDate": "2021-03-08",
        "flow": {
          "__typename": "Flow",
          "id": "1",
          "name": "Help Workflow"
        },
        "frequency": "",
        "group": {
          "__typename": "Group",
          "id": "1",
          "label": "Optin contacts"
        },
        "isActive": true,
        "isRepeating": false,
        "startAt": "2021-03-08T08:22:51Z"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                                     | Default  | Description |
| --------- | ---------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                    | required |             |
| input     | <a href="#triggerinput">TriggerInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#triggerresult">TriggerResult</a> | The updated trigger object |

## Trigger Objects

### Trigger

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
<td colspan="2" valign="top"><strong>startAt</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>endDate</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_active</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td><td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_repeating</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td><td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>frequency</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>days</strong></td>
<td valign="top">[<a href="#integer">Integer</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow_id</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>group_id</strong></td>
<td valign="top"><a href="#group">Group</a></td>
<td></td>
</tr>
</tbody>
</table>

### TriggerResult

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
<td colspan="2" valign="top"><strong>trigger</strong></td>
<td valign="top"><a href="#trigger">Trigger</a></td>
<td></td>
</tr>
</tbody>
</table>

## Trigger Inputs

### TriggerFilter

Filtering options for triggers

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
<td colspan="2" valign="top"><strong>flow_id</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
</tbody>
</table>

### TriggerInput

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
<td colspan="2" valign="top"><strong>eventType</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>isRepeating</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>frequency</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>startAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>endsAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>flowId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>GroupId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

</tbody>
</table>

### TriggerUpdateInput

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
<td colspan="2" valign="top"><strong>isRepeating</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>frequency</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>startAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>endsAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>flowId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>GroupId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

</tbody>
</table>
