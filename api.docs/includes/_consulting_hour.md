# Consulting Hours

## Get Consulting Hour by ID

```graphql
query consultingHour(id: ID!) {
  consultingHour(id: $id) {
    duration
    content
    isBillable
    insertedAt
    organizationName
    participants
    staff
    updatedAt
    when
    organization {
      name
      shortcode
    }
  }
}

{
  "id": 2
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "consultingHour": {
      "consultingHour": {
        "content": "GCS issue",
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Adam",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z",
        "organization": {
          "name": "Glific",
          "shortcode": "glific"
        }
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

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#consulting_hour_result">ConsultingHourResult</a> | The queried consulting_hour object |

## Get Consulting Hours

```graphql
query consultingHours($filter: consultingHourFilter, $opts: Opts) {
  consultingHours(filter: $filter, opts:$opts) {
    id
    content
    isBillable
    duration
    insertedAt
    participants
    staff
    organizationName
    updatedAt
    when
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "organizationName": "glific"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "consultingHours": [
      {
        "content": "GCS issue",
        "id": 2,
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Adam",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      },
      {
        "content": "Bigquery issue",
        "duration": 10,
        "insertedAt": "2021-05-04T16:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Kevin",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      }
    ]
  }
}
```

This returns all the consulting hours filtered by the input <a href="#ConsultingHourfilter">ConsultingHourfilter</a>

### Query Parameters

| Parameter | Type                                                     | Default | Description                         |
| --------- | -------------------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#ConsultingHourfilter">ConsultingHourfilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                                 | nil     | limit / offset / sort order options |

## Create a Consulting Hours

```graphql
mutation createConsultingHour($input:ConsultingHourInput!) {
  createConsultingHour(input: $input) {
    consultingHour {
      duration
      content
      isBillable
      insertedAt
      organizationId
      organizationName
      participants
      staff
      updatedAt
      when
    }
    errors {
        message
        key
    }
  }
}

{
  "input": {
    "participants": "Adam",
    "clientId": 1,
    "organizationName": "Glific",
    "staff": "Adelle Cavin",
    "content": "GCS issue",
    "when": "2021-03-08T08:22:51Z",
    "duration": 10,
    "isBillable": true,
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createConsultingHour": {
      "consultingHour": {
        "content": "GCS issue",
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Adam",
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
| input     | <a href="#consulting_hour_input">ConsultingHourInput</a> | required |             |

### Return Parameters

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#consulting_hour_result">ConsultingHourResult</a> | The created consulting hour object |


## Fetch Consulting Hours

```graphql
mutation fetchConsultingHours($input: FetchConsultingHours!) {
  fetchConsultingHours(input: $input) {
    consultingHour {
      duration
      content
      isBillable
      insertedAt
      organizationId
      organizationName
      participants
      staff
      updatedAt
      when
    }
    errors {
        message
        key
    }
  }
}

{
  "input": {
    "clientId": 1,
    "endDate": "2021-05-03",
    "startDate": "2021-05-10"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "consultingHours": [
      {
        "content": "GCS issue",
        "id": 2,
        "duration": 10,
        "insertedAt": "2021-05-04T11:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Adam",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      },
      {
        "content": "Bigquery issue",
        "duration": 10,
        "insertedAt": "2021-05-04T16:18:20Z",
        "isBillable": true,
        "organizationName": "Glific",
        "participants": "Kevin",
        "staff": "Adelle Cavin",
        "updatedAt": "2021-05-04T11:18:20Z",
        "when": "2021-03-08T08:22:51Z"
      }
    ]
  }
}
```

### Query Parameters

| Parameter | Type                                                     | Default  | Description |
| --------- | -------------------------------------------------------- | -------- | ----------- |
| input     | <a href="#fetch_consulting_hours">FetchConsultingHours</a> | required |             |


## Count all Consulting Hours

```graphql
query countConsultingHours($filter: ConsultingHourFilter) {
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

| Parameter | Type                                                     | Default | Description     |
| --------- | -------------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#ConsultingHourfilter">ConsultingHourFilter</a> | nil     | filter the list |

## Update a Consulting Hour

```graphql
mutation updateConsultingHour($id: ID!, $input:ConsultingHourInput!) {
  updateConsultingHour(id: $id!, input: $input) {
    consultingHour {
      duration
      content
      isBillable
      insertedAt
      organizationName
      participants
      staff
      updatedAt
      when
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
        "participants": "Ken",
        "clientId": 1
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
| input     | <a href="#consulting_hour_input">ConsultingHourInput</a> | required |             |

### Return Parameters

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#consulting_hour_result">ConsultingHourResult</a> | The created consulting hour object |

## Delete a Consulting Hour

```graphql
mutation  deleteConsultingHour($id: ID!) {
   deleteConsultingHour(id: $id!) {
    consultingHour {
      duration
      content
      isBillable
      insertedAt
      organizationName
      participants
      staff
      updatedAt
      when
    }
    errors {
        message
        key
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

| Type                                                       | Description                        |
| ---------------------------------------------------------- | ---------------------------------- |
| <a href="#consulting_hour_result">ConsultingHourResult</a> | The created consulting hour object |

## Consulting Hour Objects

### ConsultingHour

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
<td colspan="2" valign="top"><strong>duration</strong></td>
<td valign="top"><a href="#integer">Integer</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isBillable</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>content</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>staff</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>organization_name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>participants</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>when</strong></td>
<td valign="top"><a href="#time">Time</a></td>
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

### ConsultingHourInput

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
<td colspan="2" valign="top"><strong>duration</strong></td>
<td valign="top"><a href="#integer">Integer</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isBillable</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>content</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>staff</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>organization_name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>participants</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>when</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>client_id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### ConsultingHourResult

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
<td colspan="2" valign="top"><strong>consulting_hour</strong></td>
<td valign="top"><a href="#consulting_hour">ConsultingHour</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>
