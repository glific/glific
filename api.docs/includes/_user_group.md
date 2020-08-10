# User Group

Join table between users and groups

## Create User Group
```graphql
mutation createUserGroup($input: UserGroupInput!) {
  createUserGroup(input: $input) {
    userGroup {
      id
      user {
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
    "userId": 2,
    "groupId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createUserGroup": {
      "errors": null,
      "userGroup": {
        "group": {
          "id": "1",
          "label": "Test Group"
        },
        "id": "5",
        "user": {
          "id": "1",
          "name": "John Doe"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#usergroupinput">UserGroupInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#usergroupresult">UserGroupResult</a> | The created user group object

## Delete a UserGroup

```graphql
mutation deleteUserGroup($id: ID!) {
  deleteUserGroup(id: $id) {
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
    "deleteUserGroup": {
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
<a href="#usergroupresult">UserGroupResult</a> | An error object or empty


## UserGroup Objects

### UserGroup

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
<td colspan="2" valign="top"><strong>user</strong></td>
<td valign="top"><a href="#user">User</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### UserGroupResult

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
<td colspan="2" valign="top"><strong>userGroup</strong></td>
<td valign="top"><a href="#usergroup">UserGroup</a></td>
<td></td>
</tr>
</tbody>
</table>

## UserGroup Inputs

### UserGroupInput

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
<td colspan="2" valign="top"><strong>groupId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>userId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>
