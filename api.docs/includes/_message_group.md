# Message Group

Join table between messages and groups

## Create Message Group
```graphql
mutation createMessageGroup($input: MessageGroupInput!) {
  createMessageGroup(input: $input) {
    messageGroup {
      id
      message {
        id
        name
      }
      group {
        id
        label
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
    "messageId": 2,
    "groupId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createMessageGroup": {
      "messageGroup": {
        "message": {
          "id": "2",
          "name": "Default receiver"
        },
        "group": {
          "id": "1",
          "label": "My First Group"
        },
        "id": "1"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messagegroupinput">MessageGroupInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#messagegroupresult">MessageGroupResult</a> | The created message group object

## Delete a MessageGroup

```graphql
mutation deleteMessageGroup($id: ID!) {
  deleteMessageGroup(id: $id) {
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
    "deleteMessageGroup": {
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
<a href="#messagegroupresult">MessageGroupResult</a> | An error object or empty


## MessageGroup Objects

### MessageGroup

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
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#message">Message</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#group">Group</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### MessageGroupResult

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
<td colspan="2" valign="top"><strong>messageGroup</strong></td>
<td valign="top"><a href="#messagegroup">MessageGroup</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## MessageGroup Inputs

### MessageGroupInput

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
<td colspan="2" valign="top"><strong>messageId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>groupId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>
