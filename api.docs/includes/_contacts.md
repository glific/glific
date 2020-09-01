# Contacts

## Get All Contacts

```graphql
query contacts($filter: ContactFilter, $opts: Opts) {
  contacts(filter: $filter, opts:$opts) {
    id
    name
    optinTime
    optoutTime
    phone
    providerStatus
    status
    tags {
      id
      label
    }
    groups {
      id
      label
    }
  }
}

{
  "filter": {
    "name": "Default Receiver"
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
    "contacts": [
      {
        "groups": [],
        "id": "2",
        "name": "Default Receiver",
        "optinTime": null,
        "optoutTime": null,
        "phone": "917834811231",
        "providerStatus": "SESSION_AND_HSM",
        "status": "VALID",
        "tags": []
      }
    ]
  }
}
```
This returns all the contacts filtered by the input <a href="#contactfilter">ContactFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#contactfilter">ContactFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#contact">Contact</a>] | List of contacts


## Other filters on Contacts

```graphql
query contacts($filter: ContactFilter, $opts: Opts) {
  contacts(filter: $filter, opts: $opts) {
    id
    name
    groups {
      id
    }
    tags {
      id
    }
  }
}

{
  "filter": {
    "includeGroups": [
      1,
      2
    ],
    "includeTags": [
      1
    ]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contacts": [
      {
        "groups": [
          {
            "id": "1"
          },
          {
            "id": "2"
          }
        ],
        "id": "1",
        "name": "Glific Admin",
        "phone": "917834811114",
        "tags": [
          {
            "id": "1"
          }
        ]
      },
      {
        "groups": [
          {
            "id": "1"
          }
        ],
        "id": "2",
        "name": "Default receiver",
        "phone": "917834811231",
        "tags": [
          {
            "id": "1"
          }
        ]
      }
    ]
  }
}
```


### Return Parameters
Type | Description
| ---- | -----------
[<a href="#contact">Contact</a>] | List of contacts

## Get All Blocked Contacts

```graphql
query contacts($filter: ContactFilter, $opts: Opts) {
  contacts(filter: $filter, opts:$opts) {
    id
    phone
    status
  }
}

{
  "filter": {
    "status": "BLOCKED"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contacts": [
      {
        "id": "5",
        "phone": "7739920221",
        "status": "BLOCKED"
      }
    ]
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#contact">Contact</a>] | List of contacts


## Get a specific Contact by ID

```graphql
query contact($id: ID!) {
  contact(id: $id) {
    contact {
      id
      name
      optinTime
      optoutTime
      phone
      providerStatus
      status
      tags {
        id
        label
      }
      lastMessageAt
      language {
        label
      }
      fields
      settings
    }
  }
}

{
  "id": 5
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contact": {
      "contact": {
        "fields": "{\"name\":{\"value\":\"default\",\"type\":\"string\",\"inserted_at\":\"2020-08-28T15:34:49.192659Z\"},\"age_group\":{\"value\":\"19 or above\",\"type\":\"string\",\"inserted_at\":\"2020-08-28T15:34:55.657740Z\"}}",
        "id": "5",
        "language": {
          "label": "Hindi"
        },
        "lastMessageAt": "2020-08-28T13:15:19Z",
        "name": "Default receiver",
        "optinTime": "2020-08-28T13:15:19Z",
        "optoutTime": null,
        "phone": "917834811231",
        "providerStatus": "SESSION_AND_HSM",
        "settings": null,
        "status": "VALID",
        "tags": []
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
<a href="#contactresult">ContactResult</a> | Queried Contact

## Count all Contacts

```graphql
query countContacts($filter: ContactFilter) {
  countContacts(filter: $filter)
}

{
  "filter": {
    "status": "VALID"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countContacts": 6
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#contactfilter">ContactFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of filtered contacts

## Create a Contact

```graphql
mutation createContact($input:ContactInput!) {
  createContact(input: $input) {
    contact {
      id
      name
      optinTime
      optoutTime
      phone
      providerStatus
      status
      tags {
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
    "name": "This is a new contact for this example",
    "phone": "9876543232"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createContact": {
      "contact": {
        "id": "15",
        "name": null,
        "optinTime": null,
        "optoutTime": null,
        "phone": "9876543232",
        "providerStatus": "SESSION",
        "status": null,
        "tags": []
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#contactinput">ContactInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactresult">ContactResult</a> | The created contact object

## Update a Contact

```graphql
mutation updateContact($id: ID!, $input:ContactInput!) {
  updateContact(id: $id, input: $input) {
    contact {
      id
      name
      providerStatus
      status
      fields
      settings
      language{
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
  "id": "5",
  "input": {
    "name": "This is a updated contact for this example",
    "fields": "{\"name\":{\"value\":\"default\",\"type\":\"string\",\"inserted_at\":\"2020-08-29T05:35:38.298593Z\"},\"age_group\":{\"value\":\"19 or above\",\"type\":\"string\",\"inserted_at\":\"2020-08-29T05:35:46.623892Z\"}}",
    "languageId": 2
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateContact": {
      "contact": {
        "fields": "{\"name\":{\"value\":\"default\",\"type\":\"string\",\"inserted_at\":\"2020-08-29T05:35:38.298593Z\"},\"age_group\":{\"value\":\"19 or above\",\"type\":\"string\",\"inserted_at\":\"2020-08-29T05:35:46.623892Z\"}}",
        "id": "5",
        "language": {
          "label": "English (United States)"
        },
        "name": "This is a updated contact for this example",
        "providerStatus": "SESSION_AND_HSM",
        "settings": null,
        "status": "VALID"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#contactinput">ContactInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactresult">ContactResult</a> | The updated contact object


## Block a Contact

```graphql
mutation updateContact($id: ID!, $input:ContactInput!) {
  updateContact(id: $id, input: $input) {
    contact {
      id
      phone
      status
    }
  }
}

{
  "id": "5",
  "input": {
    "status": "BLOCKED"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateContact": {
      "contact": {
        "name": "This is a updated contact for this example",
        "phone": "7739920221",
        "status": "BLOCKED"
      },
      "errors": null
    }
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactresult">ContactResult</a> | The updated contact object

## UnBlock a Contact

```graphql
mutation updateContact($id: ID!, $input:ContactInput!) {
  updateContact(id: $id, input: $input) {
    contact {
      id
      phone
      status
    }
  }
}

{
  "id": "5",
  "input": {
    "status": "VALID"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateContact": {
      "contact": {
        "name": "This is a updated contact for this example",
        "phone": "7739920221",
        "status": "VALID"
      },
      "errors": null
    }
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactresult">ContactResult</a> | The updated contact object

## Delete a Contact

```graphql
mutation deleteContact($id: ID!) {
  deleteContact(id: $id) {
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
    "deleteContact": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteContact": {
      "errors": [
        {
          "key": "Elixir.Glific.Contacts.Contact 26",
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
<a href="#contactresult">ContactResult</a> | An error object or empty

## Get contact's location

```graphql
query contactLocation($id: ID!) {
  contactLocation(id: $id) {
    latitude
    longitude
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
    "contactLocation": {
      "latitude": -30.879910476061603,
      "longitude": 156.21478312951263
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>!

### Return Parameters
Type | Description
--------- | ---- | ------- | -----------
<a href="#location">Location</a> | A location object

## Contact Objects

### Contact

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
<td colspan="2" valign="top"><strong>optinTime</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>optoutTime</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerStatus</strong></td>
<td valign="top"><a href="#contactproviderstatusenum">ContactProviderStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top"><a href="#contactstatusenum">ContactStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>fields</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>settings</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>lastMessageAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>tags</strong></td>
<td valign="top">[<a href="#tag">Tag</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>groups</strong></td>
<td valign="top">[<a href="#group">Group</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### Location

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
<td colspan="2" valign="top"><strong>latitude</strong></td>
<td valign="top"><a href="#float">Float</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>longitude</strong></td>
<td valign="top"><a href="#float">Float</a></td>
<td></td>
</tr>
</tbody>
</table>

### ContactResult

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
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## Contact Inputs ##

### ContactFilter

Filtering options for contacts

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
<tr>
<td colspan="2" valign="top"><strong>providerStatus</strong></td>
<td valign="top"><a href="#contactproviderstatusenum">ContactProviderStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top"><a href="#contactstatusenum">ContactStatusEnum</a></td>
<td>

Match the status

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>includeTags</strong></td>
<td valign="top">[<a href="#id">id</a>]</td>
<td>

Match if contact has a tag of includeTags list

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>includeGroups</strong></td>
<td valign="top">[<a href="#id">id</a>]</td>
<td>

Match if contact is mapped in a group of includeGroups list

</td>
</tr>

</tbody>
</table>

### ContactInput

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
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>languageId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerStatus</strong></td>
<td valign="top"><a href="#contactproviderstatusenum">ContactProviderStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top"><a href="#contactstatusenum">ContactStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>fields</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>settings</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
</tbody>
</table>
