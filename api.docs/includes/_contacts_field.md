# Contacts Field

## Get Contacts Fields

```graphql
query contactsFields($filter: contactsFieldFilter, $opts: Opts) {
  contactsFields(filter: $filter, opts:$opts) {
    valueType
    updatedAt
    shortcode
    scope
    name
    insertedAt
    id
    organization {
      shortcode
      isApproved
      isActive
    }
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "name": "name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "contactsFields": [
      {
        "id": "2",
        "insertedAt": "2021-05-11T07:15:24Z",
        "name": "Age Group",
        "organization": {
          "isActive": true,
          "isApproved": false,
          "shortcode": "glific"
        },
        "scope": "contact",
        "shortcode": "age_group",
        "updatedAt": "2021-05-11T07:15:24Z",
        "valueType": "text"
      },
      {
        "id": "4",
        "insertedAt": "2021-05-13T05:52:24Z",
        "name": "Name",
        "organization": {
          "isActive": true,
          "isApproved": false,
          "shortcode": "glific"
        },
        "scope": "contact",
        "shortcode": "name",
        "updatedAt": "2021-05-13T05:52:24Z",
        "valueType": "text"
      }
    ]
  }
}
```

This returns all the contacts fields filtered by the input <a href="#ContactsFieldfilter">ContactsFieldfilter</a>

### Query Parameters

| Parameter | Type                                                   | Default | Description                         |
| --------- | ------------------------------------------------------ | ------- | ----------------------------------- |
| filter    | <a href="#ContactsFieldfilter">ContactsFieldfilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                               | nil     | limit / offset / sort order options |

## Create a Contacts Field

```graphql
mutation createContactsField($input:ContactsFieldInput!) {
  createContactsField(input: $input) {
    contactsField {
        valueType
        updatedAt
        shortcode
        scope
        name
        insertedAt
        id
        organization {
            shortcode
            isApproved
            isActive
        }
    }
    errors {
        message
        key
    }
  }
}

{
  "input": {
    "name": "School name",
    "shortcode": "school_name",
    "scope": "contact",
    "valueType": "text"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createContactsField": {
      "contactsField": {
        "id": "2",
        "insertedAt": "2021-05-13T05:52:24Z",
        "name": "School name",
        "organization": {
          "isActive": true,
          "isApproved": false,
          "shortcode": "glific"
        },
        "scope": "contact",
        "shortcode": "school name",
        "updatedAt": "2021-05-13T05:52:24Z",
        "valueType": "text"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                                     | Default  | Description |
| --------- | -------------------------------------------------------- | -------- | ----------- |
| input     | <a href="#contacts_field_input">ContactsFieldInput</a> | required |             |

### Return Parameters

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#contacts_field_result">ContactsFieldResult</a> | The created consulting hour object |

## Count all Consulting Hours

```graphql
query countConsultingHours($filter: ContactsFieldfilter) {
  countConsultingHours(filter: $filter)
}

{
  "filter": {
    "organizationName": "Glific"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countConsultingHours": 22
  }
}
```

### Query Parameters

| Parameter | Type                                                   | Default | Description     |
| --------- | ------------------------------------------------------ | ------- | --------------- |
| filter    | <a href="#ContactsFieldfilter">ContactsFieldfilter</a> | nil     | filter the list |

## Update a Consulting Hour

```graphql
mutation updateConsultingHour($id: ID!, $input:ContactsFieldInput!) {
  updateConsultingHour(id: $id!, input: $input) {
    consultingHour {
        valueType
        updatedAt
        shortcode
        scope
        name
        insertedAt
        id
        organization {
            shortcode
            isApproved
            isActive
        }
    }
    errors {
        message
        key
    }
  }
}

{
    "id": "2",
    "input": {
        "participants": "Ken"
    }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateConsultingHour": {
      "consultingHour": {
        "content": "GCS issue",
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Ken",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                                     | Default  | Description |
| --------- | -------------------------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                                    | required |             |
| input     | <a href="#consulting_hour_input">ContactsFieldInput</a> | required |             |

### Return Parameters

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#consulting_hour_result">ContactsFieldResult</a> | The created consulting hour object |

## Delete a Consulting Hour

```graphql
mutation  deleteConsultingHour($id: ID!) {
   deleteConsultingHour(id: $id!) {
    consultingHour {
        valueType
        updatedAt
        shortcode
        scope
        name
        insertedAt
        id
        organization {
            shortcode
            isApproved
            isActive
        }
    }
    errors {
        message
        key
    }
  }
}

{
    "id": "2",
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    " deleteConsultingHour": {
      "consultingHour": {
        "content": "GCS issue",
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Ken",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                                     | Description                       |
| -------------------------------------------------------- | --------------------------------- |
| <a href="#contacts_field_result">ContactsFieldResult</a> | The created contacts field object |

## Contacts Field Objects

### ContactsField

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
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value_type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>scope</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>organization</strong></td>
<td valign="top"><a href="#organization">Organization</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### ContactsFieldInput

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
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value_type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>scope</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### ContactsFieldResult

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
<td colspan="2" valign="top"><strong>contacts_field</strong></td>
<td valign="top"><a href="#contacts_field">ContactsField</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>
