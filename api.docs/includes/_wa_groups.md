# WhatsApp Groups

WhatsApp groups managed through a Maytapi account. A single WhatsApp group is one
`WaGroup` record, and the phones that belong to it are tracked as `WaGroupPhone`
memberships (each with `isPrimary` / `isActive`). The primary phone is the default
sender for the group.

## WhatsApp Groups

```graphql
query waGroups($filter: WaGroupFilter, $opts: Opts) {
  waGroups(filter: $filter, opts: $opts) {
    id
    label
    bspId
    lastCommunicationAt
    primaryPhone {
      id
      phone
      label
    }
  }
}

{
  "filter": { "term": "" },
  "opts": { "limit": 25, "offset": 0, "order": "ASC" }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "waGroups": [
      {
        "id": "1",
        "label": "Field team",
        "bspId": "120363000000000000@g.us",
        "lastCommunicationAt": "2026-05-12T10:00:00Z",
        "primaryPhone": { "id": "3", "phone": "918888888888", "label": "Primary" }
      }
    ]
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#wagroupfilter">WaGroupFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#wagroup">WaGroup</a>] | List of WhatsApp groups

## Get a WhatsApp Group

Returns one group with its primary phone and all phone memberships (for the phones
panel).

```graphql
query waGroup($id: ID!) {
  waGroup(id: $id) {
    waGroup {
      id
      label
      bspId
      lastCommunicationAt
      primaryPhone { id phone label status }
      phones {
        id
        isPrimary
        isActive
        waManagedPhone { id phone label status }
      }
    }
    errors { key message }
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
    "waGroup": {
      "waGroup": {
        "id": "1",
        "label": "Field team",
        "bspId": "120363000000000000@g.us",
        "primaryPhone": { "id": "3", "phone": "918888888888", "label": "Primary", "status": "active" },
        "phones": [
          { "id": "10", "isPrimary": true, "isActive": true,
            "waManagedPhone": { "id": "3", "phone": "918888888888", "label": "Primary", "status": "active" } },
          { "id": "11", "isPrimary": false, "isActive": true,
            "waManagedPhone": { "id": "4", "phone": "917777777777", "label": "Backup", "status": "active" } }
        ]
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required | the WhatsApp group id

### Return Parameters
Type | Description
| ---- | -----------
<a href="#wagroupresult">WaGroupResult</a> | The queried WhatsApp group

## Count WhatsApp Groups

```graphql
query waGroupsCount($filter: WaGroupFilter) {
  waGroupsCount(filter: $filter)
}

{
  "filter": { "term": "" }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": { "waGroupsCount": 12 }
}
```

## WhatsApp Managed Phones

The Maytapi phone numbers linked to the org. `status` is the Maytapi connection
state (`active`, `loading`, `expired`, ...).

```graphql
query waManagedPhones($filter: WaManagedPhoneFilter, $opts: Opts) {
  waManagedPhones(filter: $filter, opts: $opts) {
    id
    phone
    label
    status
  }
}

{
  "filter": {},
  "opts": { "limit": 25, "offset": 0, "order": "ASC" }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "waManagedPhones": [
      { "id": "3", "phone": "918888888888", "label": "Primary", "status": "active" },
      { "id": "4", "phone": "917777777777", "label": "Backup", "status": "active" }
    ]
  }
}
```

## Sync WhatsApp Managed Phone Statuses

Re-poll Maytapi and reconcile the stored `status` of every managed phone for the
org (raising a critical notification on any phone that has just transitioned into
a disconnected state). Does not provision new phones. Manager-only.

```graphql
mutation sync_wa_managed_phone_statuses {
  sync_wa_managed_phone_statuses {
    message
    errors { key message }
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sync_wa_managed_phone_statuses": {
      "message": "WhatsApp phone statuses have been refreshed.",
      "errors": null
    }
  }
}
```

## Reconnect a WhatsApp Managed Phone

Log a disconnected managed phone out of its WhatsApp session so Maytapi issues a
fresh QR/login screen to rescan. Errors if the phone is already connected
(`active`/`loading`). After calling this, poll `whatsapp_phone_screen` to render
the QR. Admin-only.

```graphql
mutation reconnect_wa_managed_phone($wa_managed_phone_id: ID!) {
  reconnect_wa_managed_phone(wa_managed_phone_id: $wa_managed_phone_id) {
    wa_managed_phone {
      id
      phone
      status
    }
    errors { key message }
  }
}

{
  "wa_managed_phone_id": 4
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "reconnect_wa_managed_phone": {
      "wa_managed_phone": { "id": "4", "phone": "917777777777", "status": "qr-screen" },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
wa_managed_phone_id | <a href="#id">ID</a> | required | the managed phone to reconnect

## WhatsApp Phone Login Screen

Fetch the QR / login screen for a managed phone so an admin can reconnect it
without logging into the Maytapi console. `code` is a `data:image/png;base64,...`
image the frontend can render, and `expires_at` hints when to refresh it (Maytapi
rotates the QR). Admin-only.

```graphql
query whatsapp_phone_screen($wa_managed_phone_id: ID!) {
  whatsapp_phone_screen(wa_managed_phone_id: $wa_managed_phone_id) {
    wa_phone_screen {
      code
      status
      expires_at
    }
    errors { key message }
  }
}

{
  "wa_managed_phone_id": 4
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "whatsapp_phone_screen": {
      "wa_phone_screen": {
        "code": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
        "status": "qr-screen",
        "expires_at": "2026-07-08T10:00:15Z"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
wa_managed_phone_id | <a href="#id">ID</a> | required | the managed phone whose screen to fetch

## Set Primary Phone

Promote a managed phone to be the group's primary. The phone must be an active
member. Demote-then-promote runs in a single transaction. Admin-only. Returns a
non-nil `warning` when the target phone's Maytapi status isn't `active` (not a
block — admins may be pre-staging a switch).

```graphql
mutation setPrimaryPhone($waGroupId: ID!, $waManagedPhoneId: ID!) {
  setPrimaryPhone(waGroupId: $waGroupId, waManagedPhoneId: $waManagedPhoneId) {
    primaryPhone {
      id
      isPrimary
      isActive
      waManagedPhone { id phone }
    }
    warning
    errors { key message }
  }
}

{
  "waGroupId": 1,
  "waManagedPhoneId": 4
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "setPrimaryPhone": {
      "primaryPhone": {
        "id": "11",
        "isPrimary": true,
        "isActive": true,
        "waManagedPhone": { "id": "4", "phone": "917777777777" }
      },
      "warning": null,
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
waGroupId | <a href="#id">ID</a> | required | the WhatsApp group id
waManagedPhoneId | <a href="#id">ID</a> | required | the managed phone to promote

## Set Primary Phone for a Collection

Set one managed phone as the primary across every WhatsApp group in a Glific
collection, in a single background action. Returns a `userJobId` to poll the skip
report. Groups where the phone is not an active member are skipped and reported.
Admin-only.

```graphql
mutation setPrimaryPhoneForCollection($collectionId: ID!, $waManagedPhoneId: ID!) {
  setPrimaryPhoneForCollection(collectionId: $collectionId, waManagedPhoneId: $waManagedPhoneId) {
    status
    userJobId
    errors { key message }
  }
}

{
  "collectionId": 1,
  "waManagedPhoneId": 4
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "setPrimaryPhoneForCollection": {
      "status": "Setting the primary phone across the collection id 1 has started in the background.",
      "userJobId": "88",
      "errors": null
    }
  }
}
```

## Collection Primary-Phone Report

Fetch the skipped-groups CSV for a completed collection primary-phone job (poll
using the `userJobId` returned above). Admin-only.

```graphql
query waGroupCollectionPrimaryReport($userJobId: ID!) {
  waGroupCollectionPrimaryReport(userJobId: $userJobId) {
    csvRows
    error
  }
}

{
  "userJobId": 88
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "waGroupCollectionPrimaryReport": {
      "csvRows": "Group,Reason\r\nMarketing (#5),not_a_member\r\nSupport (#7),member_inactive",
      "error": null
    }
  }
}
```

## Create a WhatsApp Group

Create a new WhatsApp group via Maytapi using the chosen managed phone as the
creator. Members are supplied as a CSV in `importData` (a `phone` column plus an
optional `name`); Maytapi seeds the group and a background job adds the rest.
Admin-only.

```graphql
mutation createWaGroup($input: CreateWaGroupInput!) {
  createWaGroup(input: $input) {
    waGroup { id label bspId }
    errors { key message }
  }
}

{
  "input": {
    "name": "My WhatsApp group",
    "waManagedPhoneId": 3,
    "importData": "phone,name\n919999999999,Alice\n"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createWaGroup": {
      "waGroup": { "id": "42", "label": "My WhatsApp group", "bspId": "120363111111111111@g.us" },
      "errors": null
    }
  }
}
```

## Import (Bulk-add) Contacts to a WhatsApp Group

Bulk-add members from a CSV of phone numbers (a `phone` column). Processed in the
background; returns immediately with a status. Admin-only.

```graphql
mutation importWaGroupContacts($waGroupId: ID!, $type: ImportContactsTypeEnum!, $data: String!) {
  importWaGroupContacts(waGroupId: $waGroupId, type: $type, data: $data) {
    status
    errors { message }
  }
}

{
  "waGroupId": 1,
  "type": "DATA",
  "data": "phone,name\n919999999999,Alice\n"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "importWaGroupContacts": {
      "status": "WA group member import is in progress",
      "errors": null
    }
  }
}
```

## Remove a Contact from a WhatsApp Group

Remove a contact from a WhatsApp group via Maytapi (`group/remove`). Admin-only.

```graphql
mutation removeWaGroupContact($waGroupId: ID!, $contactId: ID!) {
  removeWaGroupContact(waGroupId: $waGroupId, contactId: $contactId) {
    waGroup { id label }
    errors { key message }
  }
}

{
  "waGroupId": 1,
  "contactId": 2
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "removeWaGroupContact": {
      "waGroup": { "id": "1", "label": "Field team" },
      "errors": null
    }
  }
}
```

## Contacts in a WhatsApp Group

```graphql
query listContactWaGroup($filter: ContactWaGroupFilter, $opts: Opts) {
  listContactWaGroup(filter: $filter, opts: $opts) {
    id
    isAdmin
    contact { id name phone }
    waGroup { id label }
  }
}

{
  "filter": { "waGroupId": 1 },
  "opts": { "limit": 25, "offset": 0, "order": "ASC" }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "listContactWaGroup": [
      { "id": "5", "isAdmin": true,
        "contact": { "id": "2", "name": "Alice", "phone": "919999999999" },
        "waGroup": { "id": "1", "label": "Field team" } }
    ]
  }
}
```

## Count Contacts in a WhatsApp Group

```graphql
query countContactWaGroup($filter: ContactWaGroupFilter) {
  countContactWaGroup(filter: $filter)
}

{
  "filter": { "waGroupId": 1 }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": { "countContactWaGroup": 24 }
}
```

## Add a Contact to a WhatsApp Group

```graphql
mutation createContactWaGroup($input: ContactWaGroupInput!) {
  createContactWaGroup(input: $input) {
    contactWaGroup {
      id
      isAdmin
      contact { id name }
      waGroup { id label }
    }
    errors { key message }
  }
}

{
  "input": { "contactId": 2, "waGroupId": 1, "isAdmin": false }
}
```

## Update Contacts in a WhatsApp Group

Add and/or remove multiple contacts from a WhatsApp group in one call.

```graphql
mutation updateContactWaGroups($input: UpdateContactWaGroupsInput!) {
  updateContactWaGroups(input: $input) {
    numberDeleted
    waGroupContacts { id }
  }
}

{
  "input": {
    "waGroupId": 1,
    "addWaContactIds": [2, 3],
    "deleteWaContactIds": []
  }
}
```

## Sync WhatsApp Group Contacts

Trigger a non-destructive sync of groups and their contacts from Maytapi.

```graphql
mutation syncWaGroupContacts {
  syncWaGroupContacts {
    message
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": { "syncWaGroupContacts": { "message": "successfully synced" } }
}
```
