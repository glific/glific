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

## Update a Group with users to be added and users to be deleted

```graphql
mutation updateGroupUsers($input: GroupUsersInput!) {
  updateGroupUsers(input: $input) {
    groupUsers {
      id
      group {
        label
      }
      user {
        name
      }
    }
    numberDeleted
  }
}

{
  "input": {
    "groupId": 2,
    "addUserIds": [1, 2],
    "deleteUserIds": [3, 8]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateGroupUsers": {
      "groupUsers": [
        {
          "group": {
            "label": "Art"
          },
          "id": "10",
          "user": {
            "name": "NGO Basic User 1"
          }
        },
        {
          "group": {
            "label": "Art"
          },
          "id": "9",
          "user": {
            "name": "Glific Admin"
          }
        }
      ],
      "numberDeleted": 2
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#groupusersinput">GroupUsersInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#group_users">groupUsers</a> | The list of user groups added
integer | The number of user groups deleted

## Update groups to be added and groups to be deleted to a User

```graphql
mutation updateUserGroups($input: UserGroupsInput!) {
  updateUserGroups(input: $input) {
    userGroups {
      id
      group {
        label
      }
      user {
        name
      }
    }
    numberDeleted
  }
}

{
  "input": {
    "userId": 2,
    "addGroupIds": [1],
    "deleteGroupIds": [2, 3]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateUserGroups": {
      "numberDeleted": 2,
      "userGroups": [
        {
          "group": {
            "label": "Poetry"
          },
          "id": "13",
          "user": {
            "name": "NGO Basic User 1"
          }
        }
      ]
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#usergroupsinput">UserGroupsInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#user_groups">userGroups</a> | The list of user groups added
integer | The number of user groups deleted

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

### GroupUsersInput ###

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
<td colspan="2" valign="top"><strong>GroupId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>AddUserIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>DeleteUserIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### UserGroupsInput ###

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
<td colspan="2" valign="top"><strong>UserId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>AddGroupIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>DeleteGroupIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
</tbody>
</table>
