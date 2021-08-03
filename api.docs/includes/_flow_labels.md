# FlowLabels

## Get All FlowLabels

```graphql
query flowLabels($filter: FlowLabelFilter, $opts: Opts) {
  flowLabels(filter: $filter, opts: $opts) {
    id
    insertedAt
    name
    uuid
    updatedAt
  }
}

{
  "opts": {
    "limit": 2,
    "offset": 0,
    "order": "ASC"
  },
  "filter": {
    "name": "Age Group 11 to 14"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "flowLabels": [
      {
        "id": "2",
        "insertedAt": "2021-08-03T09:55:28Z",
        "name": "Age Group 11 to 14",
        "updatedAt": "2021-08-03T09:55:28Z",
        "uuid": "43f0122d-5fdc-4800-b8e9-3987d086197d"
      }
    ]
  }
}
```

This returns all the flow labels

### Query Parameters

| Parameter | Type                                           | Default | Description                         |
| --------- | ---------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#flowlabelfilter">FlowLabelFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                       | nil     | limit / offset / sort order options |

### Return Parameters

| Type                                 | Description         |
| ------------------------------------ | ------------------- |
| [<a href="#flowlabel">FlowLabel</a>] | List of flow labels |

## Get a specific FlowLabel by ID

```graphql
query flow($id: ID!) {
  flow(id: $id) {
    flow {
      id
      name
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
    "flow": {
      "flow": {
        "id": "1",
        "name": "Age Group 11 to 14"
      }
    }
  }
}
```

### Return Parameters

| Type                                           | Description       |
| ---------------------------------------------- | ----------------- |
| <a href="#flowlabelresult">FlowLabelResult</a> | Queried FlowLabel |

## Count all FlowLabels

```graphql
query countFlowLabels($filter: FlowLabelFilter) {
  countFlowLabels(filter: $filter)
}

{
  "filter": {
    "name": "Age Group 11 to 14"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countFlowLabels": 2
  }
}
```

## FlowLabel Objects

### FlowLabel

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
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#uuid4">UUID4</a></td>
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

### FlowLabelResult

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
<td colspan="2" valign="top"><strong>flowlabel</strong></td>
<td valign="top"><a href="#flowlabel">FlowLabel</a></td>
<td></td>
</tr>
</tbody>
</table>

## FlowLabel Inputs

### FlowLabelInput

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
</tbody>
</table>

### FlowLabelFilter

Filtering options for flowlabels

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
  <td>Match the flow label name</td>
</tr>
</tbody>
</table>
