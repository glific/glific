# Triggers

## Get All Triggers

```graphql
query triggers($filter: TriggerFilter) {
  triggers(filter: $filter) {
      id
      name
      eventType
      triggerAction {
        id
        flow {
          id
          name
        }
        group {
          id
          label
        }
      }
      triggerCondition {
        id
        frequency
        endsAt
        startAt
        isActive
        isRepeating
      }
    }
}

{
  "filter": {
    "name": "test trigger"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "triggers": [
      {
        "eventType": "start_flow",
        "id": "1",
        "name": "test trigger",
        "triggerAction": {
          "flow": {
            "id": "2",
            "name": "Language Workflow"
          },
          "group": {
            "id": "1",
            "label": "Default Group"
          },
          "id": "1"
        },
        "triggerCondition": {
          "endsAt": "2020-12-29T13:15:19Z",
          "frequency": "today",
          "id": "1",
          "isActive": true,
          "isRepeating": false,
          "startAt": "2020-12-29T13:15:19Z"
        }
      }
    ]
  }
}
```
This returns all the triggers for the organization filtered by the input <a href="#triggerfilter">TriggerFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#triggerfilter">TriggerFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Get a specific Trigger by ID

```graphql
query trigger($id: ID!) {
  trigger(id: $id) {
    trigger {
      id
      name
      eventType
      triggerAction {
        id
        flow {
          id
          name
        }
        group {
          id
          label
        }
      }
      triggerCondition {
        id
        frequency
        endsAt
        startAt
        isActive
        isRepeating
      }
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
        "eventType": "start_flow",
        "id": "1",
        "name": "test trigger",
        "triggerAction": {
          "flow": {
            "id": "2",
            "name": "Language Workflow"
          },
          "group": {
            "id": "1",
            "label": "Default Group"
          },
          "id": "1"
        },
        "triggerCondition": {
          "endsAt": "2020-12-29T13:15:19Z",
          "frequency": "today",
          "id": "1",
          "isActive": true,
          "isRepeating": false,
          "startAt": "2020-12-29T13:15:19Z"
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

## Count all Triggers

```graphql
query countTriggers($filter: TriggerFilter) {
  countTriggers(filter: $filter)
}

{
  "filter": {
    "name": test
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

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#triggerfilter">TriggerFilter</a> | nil | filter the list

## Create a Trigger

```graphql
mutation createTrigger($input: TriggerInput!) {
  createTrigger(input: $input) {
    trigger{
      id
      name
      eventType
      triggerAction {
        id
        flow {
          id
          name
        }
        group {
          id
          label
        }
      }
      triggerCondition {
        id
        frequency
        endsAt
        startAt
        isActive
        isRepeating
      }
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "name": "test",
    "eventType": "start_flow",
    "flowId": 1,
    "groupId": 1,
    "startAt": "2020-12-30T13:15:19Z",
    "endsAt": "2020-12-29T13:15:19Z"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createTrigger": {
      "errors": null,
      "trigger": {
        "eventType": "start_flow",
        "id": "2",
        "name": "test",
        "triggerAction": {
          "flow": {
            "id": "1",
            "name": "Help Workflow"
          },
          "group": {
            "id": "1",
            "label": "Default Group"
          },
          "id": "2"
        },
        "triggerCondition": {
          "endsAt": "2020-12-30T13:15:19Z",
          "frequency": "today",
          "id": "2",
          "isActive": true,
          "isRepeating": false,
          "startAt": "2020-12-29T13:15:19Z"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#triggerinput">TriggerInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#triggerresult">TriggerResult</a> | The created trigger object

## Update a Trigger

```graphql
mutation updateTrigger($id: ID!, $input: TriggerUpdateInput!) {
  updateTrigger(id: $id, input: $input) {
    trigger {
      id
      name
      eventType
      triggerAction {
        id
        flow {
          id
          name
        }
        group {
          id
          label
        }
      }
      triggerCondition {
        id
        frequency
        endsAt
        startAt
        isActive
        isRepeating
      }
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
      "errors": null,
      "trigger": {
        "eventType": "start_flow",
        "id": "1",
        "name": "test trigger",
        "triggerAction": {
          "flow": {
            "id": "2",
            "name": "Language Workflow"
          },
          "group": {
            "id": "1",
            "label": "Default Group"
          },
          "id": "1"
        },
        "triggerCondition": {
          "endsAt": "2020-12-29T13:15:19Z",
          "frequency": "today",
          "id": "1",
          "isActive": true,
          "isRepeating": false,
          "startAt": "2020-12-29T13:15:19Z"
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
input | <a href="#triggerinput">TriggerInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#triggerresult">TriggerResult</a> | The updated trigger object



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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>eventType</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>triggerAction</strong></td>
<td valign="top"><a href="#triggeraction">TriggerAction</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>triggerCondition</strong></td>
<td valign="top"><a href="#triggercondition">TriggerCondition</a></td>
<td></td>
</tr>
</tbody>
</table>

### TriggerAction

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
<td colspan="2" valign="top"><strong>actionType</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#group">Group</a></td>
<td></td>
</tr>
</tbody>
</table>

### TriggerCondition

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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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
<td colspan="2" valign="top"><strong>fireAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
</tbody>
</table>

### TriggerResult ###

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

## Trigger Inputs ##


### TriggerFilter ###

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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the name</td>
</tr>
</tbody>
</table>

### TriggerInput ###

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

### TriggerUpdateInput ###

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
