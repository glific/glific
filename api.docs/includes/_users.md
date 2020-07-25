# Users

## Get All Users

```graphql
query users($filter: UserFilter, $opts: Opts) {
  users(filter: $filter, opts:$opts) {
    id
    name
    phone
    roles
  }
}

{
  "filter": {
    "name": "Doe"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "users": [
      {
        "id": "1",
        "name": "John Doe",
        "phone": "+919820198765",
        "roles": [
          "admin"
        ]
      },
      {
        "id": "2",
        "name": "Jane Doe",
        "phone": "+918820198765",
        "roles": [
          "basic",
          "admin"
        ]
      }
    ]
  }
}
```
This returns all the users filtered by the input <a href="#userfilter">UserFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#userfilter">UserFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#user">User</a>] | List of users

## Get a specific User by ID

```graphql
query user($id: ID!) {
  user(id: $id) {
    user {
      id
      name
      phone
      roles
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
    "user": {
      "user": {
        "id": "1",
        "name": "John Doe",
        "phone": "+919820198765",
        "roles": [
          "admin"
        ]
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a> | nil ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#userresult">UserResult</a> | Queried User

## Count all Users

```graphql
query countUsers($filter: UserFilter) {
  countUsers(filter: $filter)
}

{
  "filter": {
    "name": "John"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countUsers": 1
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#userfilter">UserFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of filtered users

## Update a User

```graphql
mutation updateUser($id: ID!, $input:UserInput!) {
  updateUser(id: $id, input: $input) {
    user {
      id
      name
      phone
      roles
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "2",
  "input": {
    "name": "Updated Name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateUser": {
      "errors": null,
      "user": {
        "id": "2",
        "name": "Updated Name",
        "phone": "+918820198765",
        "roles": [
          "basic",
          "admin"
        ]
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#userinput">UserInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#userresult">UserResult</a> | The updated user object


## Delete a User

```graphql
mutation deleteUser($id: ID!) {
  deleteUser(id: $id) {
    errors {
      key
      message
    }
  }
}

{
  "id": "2"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteUser": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteUser": {
      "errors": [
        {
          "key": "Elixir.Glific.Users.User 2",
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
Type | Description
--------- | ---- | ------- | -----------
<a href="#userresult">UserResult</a> | An error object or empty

## User Objects

### User

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
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>roles</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>Users</strong></td>
<td valign="top">[<a href="#users">Users</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### UserResult

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
<td colspan="2" valign="top"><strong>user</strong></td>
<td valign="top"><a href="#user">User</a></td>
<td></td>
</tr>
</tbody>
</table>

## User Inputs ##

### UserFilter

Filtering options for users

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
<td>

Match the name

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the phone

</td>
</tr>
</tbody>
</table>

### UserInput

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
<td colspan="2" valign="top"><strong>roles</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
</tbody>
</table>
