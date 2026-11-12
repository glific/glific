# Contacts

## Get All Contacts

```graphql
query contacts($filter: ContactFilter, $opts: Opts) {
  contacts(filter: $filter, opts:$opts) {
    id
    name
    optinTime
    optoutTime
    optinMethod
    optoutMethod
    phone
    maskedPhone
    bspStatus
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
        "optinMethod": null,
        "optoutMethod": null,
        "phone": "917834811231",
        "maskedPhone": "9178******31",
        "bspStatus": "SESSION_AND_HSM",
        "status": "VALID",
        "tags": []
      }
    ]
  }
}
```

This returns all the contacts filtered by the input <a href="#contactfilter">ContactFilter</a>

### Query Parameters

| Parameter | Type                                       | Default | Description                         |
| --------- | ------------------------------------------ | ------- | ----------------------------------- |
| filter    | <a href="#contactfilter">ContactFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                   | nil     | limit / offset / sort order options |

### Return Parameters

| Type                             | Description      |
| -------------------------------- | ---------------- |
| [<a href="#contact">Contact</a>] | List of contacts |

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

| Type                             | Description      |
| -------------------------------- | ---------------- |
| [<a href="#contact">Contact</a>] | List of contacts |

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

| Type                             | Description      |
| -------------------------------- | ---------------- |
| [<a href="#contact">Contact</a>] | List of contacts |

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
      bspStatus
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
      history {
        eventType
        eventLabel
        eventMeta
      }
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
        "bspStatus": "SESSION_AND_HSM",
        "settings": null,
        "status": "VALID",
        "tags": [],
        "history": [
          {
            "eventLabel": "All contact flows are ended.",
            "eventMeta": "{}",
            "eventType": "contact_flow_ended_all"
          },
          {
            "eventLabel": "Flow (Contact History Flows) started for the contact",
            "eventMeta": "{\"flow_name\":\"Contact History Flows\",\"flow_id\":14,\"context_id\":6}",
            "eventType": "contact_flow_started"
          },
          {
            "eventLabel": "Value for new_field is updated to Value 1",
            "eventMeta": "{\"value\":\"Value 1\",\"old_value\":{\"value\":\"value 2\",\"type\":\"string\",\"label\":\"new_field\",\"inserted_at\":\"2021-12-02T09:12:12.007578Z\"},\"new_value\":\"Value 1\",\"label\":\"new_field\",\"field\":\"new_field\"}",
            "eventType": "contact_fields_updated"
          }
        ]
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                 | Default | Description |
| --------- | -------------------- | ------- | ----------- |
| ID        | <a href="#id">ID</a> | nil     |             |

### Return Parameters

| Type                                       | Description     |
| ------------------------------------------ | --------------- |
| <a href="#contactresult">ContactResult</a> | Queried Contact |

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

| Parameter | Type                                       | Default | Description     |
| --------- | ------------------------------------------ | ------- | --------------- |
| filter    | <a href="#contactfilter">ContactFilter</a> | nil     | filter the list |

### Return Parameters

| Type                   | Description                |
| ---------------------- | -------------------------- |
| <a href="#int">Int</a> | Count of filtered contacts |

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
      bspStatus
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
        "bspStatus": "SESSION",
        "status": null,
        "tags": []
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                     | Default  | Description |
| --------- | ---------------------------------------- | -------- | ----------- |
| input     | <a href="#contactinput">ContactInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#contactresult">ContactResult</a> | The created contact object |

`input` may also carry an optional `channel` (default `WHATSAPP`, which needs a `phone`) and an `identifier`. With
`channel: WEB` the `identifier` (the username the contact logs in with, stored lowercase) is required, no phone is
needed, the web channel must be enabled for the organization, and the contact's `identities` field lists its `WEB`
identity.

## Update a Contact

```graphql
mutation updateContact($id: ID!, $input:ContactInput!) {
  updateContact(id: $id, input: $input) {
    contact {
      id
      name
      bspStatus
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
          "label": "English"
        },
        "name": "This is a updated contact for this example",
        "bspStatus": "SESSION_AND_HSM",
        "settings": null,
        "status": "VALID"
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
| input     | <a href="#contactinput">ContactInput</a> | required |             |

### Return Parameters

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#contactresult">ContactResult</a> | The updated contact object |

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

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#contactresult">ContactResult</a> | The updated contact object |

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

| Type                                       | Description                |
| ------------------------------------------ | -------------------------- |
| <a href="#contactresult">ContactResult</a> | The updated contact object |

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

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                       | Description              |
| ------------------------------------------ | ------------------------ |
| <a href="#contactresult">ContactResult</a> | An error object or empty |

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

| Parameter | Type                  | Default | Description |
| --------- | --------------------- | ------- | ----------- |
| id        | <a href="#id">ID</a>! |

### Return Parameters

| Type                             | Description       |
| -------------------------------- | ----------------- |
| <a href="#location">Location</a> | A location object |

## Optin a Contact

```graphql
mutation optinContact($phone: String, $name: String, $channel: MessageChannelEnum, $identifier: String) {
  optinContact(phone: $phone, name: $name, channel: $channel, identifier: $identifier) {
    contact {
      id
      phone
      name
      lastMessageAt
      optinTime
      bspStatus
    }
    errors {
      key
      message
    }
  }
}

{
  "phone": "917834811119",
  "name": "contact name"
}

# On the web channel
{
  "channel": "WEB",
  "identifier": "ravi_12",
  "name": "Ravi"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "optinContact": {
      "contact": {
        "bspStatus": "HSM",
        "id": "100",
        "lastMessageAt": null,
        "name": "contact name",
        "optinTime": "2020-11-25T16:12:18Z",
        "phone": "917834811119"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter  | Type                                                 | Default  | Description |
| ---------- | ---------------------------------------------------- | -------- | ----------- |
| phone      | <a href="#string">String</a>                         |          | The WhatsApp number. Required on `WHATSAPP` |
| name       | <a href="#string">String</a>                         |          | The contact's name, used when the contact is created |
| channel    | <a href="#messagechannelenum">MessageChannelEnum</a> | WHATSAPP | The channel to opt the contact in on |
| identifier | <a href="#string">String</a>                         |          | The web username. Required on `WEB` |

Opts a contact in on one channel, creating the contact when it does not exist. On `WHATSAPP` the
contact is found by `phone`. On `WEB` it is found by `identifier`, and the consent is recorded for the
web channel only: it does not opt the contact in on WhatsApp, and a repeated opt-in keeps the first
one. `WEB` needs the web channel to be enabled for the organization.

### Return Parameters

| Type                                       | Description    |
| ------------------------------------------ | -------------- |
| <a href="#contactresult">ContactResult</a> | contact object |

## Get a simulator contact

Gets a simulator contact for the logged in user. We are currently returning the same simulator
for the same user ID. We will revisit this protocol and potentially pass the user token instead
to get a different simulator for different sessions for the same logged in user.

```graphql
query simulatorGet() {
  simulatorGet {
    id
    name
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "simulatorGet": {
      "id": "2",
      "name": "Simulator"
    }
  }
}

OR if no simulator is available

{
  "data": {
    "simulatorGet": null
  }
}
```

### Query Parameters

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |

### Return Parameters

| Type                           | Description      |
| ------------------------------ | ---------------- |
| <a href="#contact">Contact</a> | A contact object |

## Release a simulator contact

Releases a simulator contact for the logged in user if one exists. The system also releases the simulator
when it has been idle for more than 10 minutes and there is a request for a simulator

```graphql
query simulatorRelease {
  simulatorRelease {
    id
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "simulatorRelease": null
  }
}
```

### Query Parameters

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |

### Return Parameters

| Type | Description |
| ---- | ----------- |

## Get All Contact History

```graphql
query ContactHistory($filter: ContactsHistoryFilter, $opts: Opts) {
    contactHistory(filter: $filter, opts: $opts) {
      eventDatetime
      eventLabel
      eventMeta
      eventType
      id
      insertedAt
      updatedAt
    }
  }


{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "contactId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contactHistory": [
      {
        "eventDatetime": "2021-12-07T12:12:50Z",
        "eventLabel": "All contact flows are ended.",
        "eventMeta": "{}",
        "eventType": "contact_flow_ended_all",
        "id": "106",
        "insertedAt": "2021-12-07T12:12:51.000000Z",
        "updatedAt": "2021-12-07T12:12:51.000000Z"
      },
      {
        "eventDatetime": "2021-12-07T12:12:50Z",
        "eventLabel": "Flow Started",
        "eventMeta": "{\"flow\":{\"uuid\":\"3fa22108-f464-41e5-81d9-d8a298854429\",\"name\":\"Help Workflow\",\"id\":1},\"context_id\":70}",
        "eventType": "contact_flow_started",
        "id": "107",
        "insertedAt": "2021-12-07T12:12:51.000000Z",
        "updatedAt": "2021-12-07T12:12:51.000000Z"
      },
      {
        "eventDatetime": "2021-12-07T12:12:50Z",
        "eventLabel": "Flow Ended:",
        "eventMeta": "{\"flow\":{\"uuid\":\"3fa22108-f464-41e5-81d9-d8a298854429\",\"name\":\"Help Workflow\",\"id\":1},\"context_id\":70}",
        "eventType": "contact_flow_ended",
        "id": "108",
        "insertedAt": "2021-12-07T12:12:51.000000Z",
        "updatedAt": "2021-12-07T12:12:51.000000Z"
      }
    ]
  }
}
```

This returns all the contact history for the contact filtered by the input <a href="#contactHistoryFilter">contactHistoryFilter</a>

### Query Parameters

| Parameter | Type                                                     | Default | Description                         |
| --------- | -------------------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#contactHistoryFilter">contactHistoryFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                                 | nil     | limit / offset / sort order options |

## Count all ContactHistory

```graphql
query countContactHistory($filter: ContactsHistoryFilter) {
  countContactHistory(filter: $filter)
}


{
  "filter": {
    "contact_id": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countContactHistory": 3
  }
}
```

### Query Parameters

| Parameter | Type                                                     | Default | Description     |
| --------- | -------------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#contactHistoryFilter">contactHistoryFilter</a> | nil     | filter the list |

## Add an Identity to a Contact

```graphql
mutation addContactIdentity($contactId: ID!, $channel: MessageChannelEnum!, $identifier: String!) {
  addContactIdentity(contactId: $contactId, channel: $channel, identifier: $identifier) {
    contact {
      id
      name
      identities {
        channel
        identifier
      }
    }
    errors {
      key
      message
    }
  }
}
```

> With variables:

```json
{ "contactId": "15", "channel": "WEB", "identifier": "ravi_12" }
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "addContactIdentity": {
      "contact": { "id": "15", "name": "Ravi", "identities": [{ "channel": "WEB", "identifier": "ravi_12" }] },
      "errors": null
    }
  }
}
```

Gives an existing contact a <a href="#web-channel-login">web channel</a> username. Only the `WEB` channel is
accepted: a `WHATSAPP` identity is the contact's phone and follows it. Adding a username the contact already has
succeeds without change; a username held by another contact is refused (`identifier: has already been taken`) and
never moved. Requires the manager role and the web channel enabled for the organization.

| Parameter  | Type               | Description                                                                 |
| ---------- | ------------------ | --------------------------------------------------------------------------- |
| contactId  | ID                 | The contact to add the identity to.                                         |
| channel    | MessageChannelEnum | The channel of the identity. Only `WEB` is accepted.                        |
| identifier | String             | The username: letters, digits, `_`, `@` and `.`, stored lowercase (case-insensitive), 1 to 255 characters. |

To create a contact for a web username before its first login, use <a href="#create-a-contact">createContact</a>
with `channel: WEB` and an `identifier`.

## Get a Contact by Identity

```graphql
query contactByIdentity($channel: MessageChannelEnum!, $identifier: String!) {
  contactByIdentity(channel: $channel, identifier: $identifier) {
    contact {
      id
      name
      identities {
        channel
        identifier
      }
    }
    errors {
      key
      message
    }
  }
}
```

> With variables:

```json
{ "channel": "WEB", "identifier": "ravi_12" }
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contactByIdentity": {
      "contact": {
        "id": "15",
        "name": "Ravi",
        "identities": [{ "channel": "WEB", "identifier": "ravi_12" }]
      },
      "errors": null
    }
  }
}
```

Finds the contact that logs in with an identifier on a channel, for example a web channel username.
Web identifiers are case-insensitive. It never creates a contact; an unknown identifier returns an
error. Requires the manager role: identifiers are personal data, and the `identities` field of a
contact is empty for a staff user.

| Parameter  | Type                                   | Description                          |
| ---------- | -------------------------------------- | ------------------------------------ |
| channel    | MessageChannelEnum | `WEB` or `WHATSAPP`.   |
| identifier | String                                 | The username, or the phone number.   |

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
<td colspan="2" valign="top"><strong>identities</strong></td>
<td valign="top">[ContactIdentity]</td>
<td>How the contact logs in on each channel (<code>id</code>, <code>channel</code>, <code>identifier</code>, <code>insertedAt</code>). Empty for a staff user.</td>
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
<td colspan="2" valign="top"><strong>optinMethod</strong></td>
<td valign="top"><a href="#datetime">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>optoutMethod</strong></td>
<td valign="top"><a href="#datetime">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>maskedPhone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>bspStatus</strong></td>
<td valign="top"><a href="#contactproviderstatusenum">ContactProviderStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top"><a href="#contactstatusenum">ContactStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isOrgRead</strong></td>
<td valign="top"><a href="#datetime">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isOrgReplied</strong></td>
<td valign="top"><a href="#datetime">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isContactReplied</strong></td>
<td valign="top"><a href="#datetime">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>LastMessageNumber</strong></td>
<td valign="top"><a href="#datetime">Integer</a></td>
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
<td colspan="2" valign="top"><strong>lastCommunicationAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
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
<tr>
<td colspan="2" valign="top"><strong>history</strong></td>
<td valign="top"><a href="#contacthistory">History</a></td>
<td></td>
</tr>
</tbody>
</table>

### ContactHistory

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
<td colspan="2" valign="top"><strong>event_type</strong></td>
<td valign="top"><a href="#string">Event Type</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>event_label</strong></td>
<td valign="top"><a href="#string">Event Label</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>event_meta</strong></td>
<td valign="top"><a href="#json">Event Meta</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>event_datetime</strong></td>
<td valign="top"><a href="#datetime">Event DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>profile</strong></td>
<td valign="top"><a href="#profile">Profile</a></td>
<td></td>
</tr>

</tbody>
</table>

### contactHistoryFilter

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
<td colspan="2" valign="top"><strong>profile_id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>event_type</strong></td>
<td valign="top"><a href="#string">Event Type</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>event_label</strong></td>
<td valign="top"><a href="#string">Event Label</a></td>
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

### ContactHistoryResult

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
<td colspan="2" valign="top"><strong>contactHistory</strong></td>
<td valign="top"><a href="#contacthistory">ContactHistory</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## Contact Inputs

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
<td colspan="2" valign="top"><strong>term</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td valign="top">Filter by name or phone</td>
<td>

Match the name

</td>
</tr>

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
<td colspan="2" valign="top"><strong>bspStatus</strong></td>
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
<td colspan="2" valign="top"><strong>bspStatus</strong></td>
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
