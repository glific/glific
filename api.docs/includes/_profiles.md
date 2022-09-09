# Profiles

## Get All Profiles

```graphql
query profiles($filter: ProfileFilter, $opts: Opts) {
  profiles(filter: $filter, opts:$opts) {
    id
    name
    type
    fields
  }
}

{
  "filter": {
    "name": "user"
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
    "profiles": [
      {
        "fields": "{}",
        "id": "6",
        "name": "user",
        "type": "profile"
      }
    ]
  }
}
```

This returns all the profiles filtered by the input <a href="#profilefilter">ProfileFilter</a>

### Query Parameters

| Parameter | Type                                       | Default | Description                         |
| --------- | ------------------------------------------ | ------- | ----------------------------------- |
| filter    | <a href="#profilefilter">ProfileFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                   | nil     | limit / offset / sort order options |

### Return Parameters

| Type                             | Description      |
| -------------------------------- | ---------------- |
| [<a href="#profile">Profile</a>] | List of profiles |



## Create a Profile

```graphql
mutation createProfile($input:ProfileInput!) {
  createProfile(input: $input) {
    profile {
      id
      name
      type
      fields
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "name": "This is a new profile",
    "type": "profile"
  }
}
```

> The above query returns JSON structured like this:

```json
{
   "data": {
     "createProfile": {
       "errors": null,
       "profile": {
         "id": "6",
         "name": "user",
         "fields": "{}",
         "type": "profile"
       }
     }
   }
}
```

### Query Parameters

| Parameter | Type                                     | Default  | Description |
| --------- | ---------------------------------------- | -------- | ----------- |
| input     | <a href="#profileinput">ProfileInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#profileresult">ProfileResult</a> | The created profile object |

## Update a Profile

```graphql
mutation updateProfile($input:ProfileInput!) {
  updateProfile(input: $input) {
    profile {
      id
      name
      type
      fields
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "id": "6",
    "name": "This is a new profile",
    "type": "profile user"
  }
}
```

```json
{
  "data": {
    "updateProfile": {
      "profile": {
        "id": "6",
        "name": "This is a new profile",
        "type": "profile user"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                     | Default  | Description |
| --------- | ---------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                    | required |             |
| input     | <a href="#profileinput">ProfileInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#profileresult">ProfileResult</a> | The updated profile object |

## Delete a Profile

```graphql
mutation deleteProfile($id: ID!) {
  deleteProfile(id: $id) {
    errors {
      key
      message
    }
  }
}

{
  "id": "26"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteProfile": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteProfile": {
      "errors": [
        {
          "key": "Elixir.Glific.Profiles.Profile 26",
          "message": "Resource not found"
        }
      ]
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                       | Description              |
| ------------------------------------------ | ------------------------ |
| <a href="#profileresult">ProfileResult</a> | An error object or empty |

## Profile Objects

### Profile

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
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>fields</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
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

### profileFilter

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
<td colspan="2" valign="top"><strong>contact_id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>organization_id</strong></td>
<td valign="top"><a href="#string">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">Name</a></td>
<td></td>
</tr>

</tbody>
</table>

### ProfileResult

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
<td colspan="2" valign="top"><strong>profile</strong></td>
<td valign="top"><a href="#profile">Profile</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### ProfileInput

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
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>fields</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contactId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contactId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>


