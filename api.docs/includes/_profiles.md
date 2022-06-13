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


