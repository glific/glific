# Profiles

## Get All Profiles

```graphql
query profiles($filter: ProfileFilter, $opts: Opts) {
  profiles(filter: $filter, opts:$opts) {
    id
    name
    profileType
    profileRegistrationFields
    contactProfileFields
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
        "contactPprofileFields": "{}",
        "id": "6",
        "name": "user",
        "profileRegistrationFields": "{}",
        "profile_type": "profile"
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
      profileType
      profileRegistrationFields
      contactProfileFields
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
    "profile_type": "profile"
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
         "contactPprofileFields": "{}",
         "id": "6",
         "name": "user",
         "profileRegistrationFields": "{}",
         "profile_type": "profile"
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
      profileType
      profileRegistrationFields
      contactProfileFields
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
    "profileType": "profile user"
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
        "profileType": "profile user"
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