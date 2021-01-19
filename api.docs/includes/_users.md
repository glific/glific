# Users

## Get All Roles
```graphql
query {
  roles
}
```

> The above query returns JSON structured like this:

```json

{
  "data": {
    "roles": [
         "none",
         "staff",
         "manager",
         "admin"
    ]
  }
}
```
This returns all the roles

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#string">Role</a>] | List of roles

## Get All Users

```graphql
query users($filter: UserFilter, $opts: Opts) {
  users(filter: $filter, opts:$opts) {
    id
    name
    phone
    roles
    groups {
      label
    }
  }
}

{
  "filter": {
    "name": "Doe"
  },
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "users": [
      {
        "groups": [],
        "id": "1",
        "name": "John Doe",
        "phone": "+919820198765",
        "roles": [
          "admin"
        ]
      },
      {
        "groups": [
          {
            "label": "First Group"
          }
        ],
        "id": "2",
        "name": "Jane Doe",
        "phone": "+918820198765",
        "roles": [
          "staff",
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

## Get Current User

```graphql
query currentUser {
  currentUser {
    user {
      id
      name
      phone
      roles
      organization {
        activeLanguages {
          label
        }
      }
    }
  }
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
          "Admin"
        ],
        "organization": {
          "activeLanguages": [
            {
              "label": "English (United States)"
            }
          ]
        },
      }
    }
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
<a href="#userresult">UserResult</a> | Current User

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
mutation updateUser($id: ID!, $input: UserInput!) {
  updateUser(id: $id, input: $input) {
    user {
      id
      name
      phone
      roles
      groups {
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
  "id": "2",
  "input": {
    "name": "Updated Name",
    "roles": [
      "admin"
    ],
    "groupIds": [
      1,
      2
    ]
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
        "groups": [
          {
            "label": "First Group"
          },
          {
            "label": "Poetry Group"
          }
        ],
        "id": "2",
        "name": "Updated Name",
        "phone": "919876543210",
        "roles": [
          "admin"
        ]
      }
    }
  }
}
```

> In case of errors, above function returns an error object like the below

```
{
  "data": {
    "updateUser": {
      "errors": [
        {
          "key": "roles",
          "message": "has an invalid entry"
        }
      ],
      "user": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#userinput">UserInput</a> | required ||
groupIds | [<a href="#id">ID</a>] | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#userresult">UserResult</a> | The updated user object


## Update Current User Details

```graphql
mutation updateCurrentUser($input:CurrentUserInput!) {
  updateCurrentUser(input: $input) {
    user {
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
  "input": {
    "name": "Updated Name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateCurrentUser": {
      "errors": null,
      "user": {
        "id": "2",
        "name": "Updated Name"
      }
    }
  }
}
```

Current User can update only the name and password, but not the phone number

## Update Current User Password

```graphql
mutation updateCurrentUser($input:CurrentUserInput!) {
  updateCurrentUser(input: $input) {
    user {
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
  "input": {
    "name": "Updated Name",
    "otp": "340606",
    "password": "new_password"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateCurrentUser": {
      "errors": null,
      "user": {
        "id": "2",
        "name": "Updated Name"
      }
    }
  }
}
```

> In case of otp errors, above function returns an error object like the below

```
{
  "data": {
    "updateCurrentUser": {
      "errors": [
        {
          "key": "OTP",
          "message": "does_not_exist"
        }
      ],
      "user": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#currentuserinput">CurrentUserInput</a> | required ||

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
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
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
<td colspan="2" valign="top"><strong>groups</strong></td>
<td valign="top">[<a href="#group">Group</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isRestricted</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>insertedAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>updatedAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
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

### Role

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
<td valign="top"><a href="#ID">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
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
<tr>
<td colspan="2" valign="top"><strong>groupIds</strong></td>
<td valign="top">[<a href="#id">ID</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isRestricted</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

### CurrentUserInput

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
<td colspan="2" valign="top"><strong>otp</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>password</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>
