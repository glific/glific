# Sheets

## Get All Sheets

```graphql
query Sheets($filter: SheetFilter, $opts: Opts) {
  sheets(filter: $filter, opts: $opts) {
    id
    url
    isActive
    label
    lastSyncedAt
    insertedAt
    updatedAt
  }
}

{
  "filter": {
    "label": "sheet"
  },
  "opts": {
    "limit": 25,
    "offset": 0,
    "order": "ASC"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sheets": [
      {
        "id": "1",
        "insertedAt": "2022-10-14T05:37:33.000000Z",
        "isActive": true,
        "label": "sheet1",
        "lastSyncedAt": "2022-10-14T05:37:32Z",
        "updatedAt": "2022-10-14T05:37:33.000000Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      },
      {
        "id": "2",
        "insertedAt": "2022-10-14T05:42:19.000000Z",
        "isActive": true,
        "label": "sheet2",
        "lastSyncedAt": "2022-10-14T05:42:19Z",
        "updatedAt": "2022-10-14T05:42:19.000000Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      }
    ]
  }
}
```

This returns all the sheets

### Query Parameters

| Parameter | Type                                   | Default | Description                         |
| --------- | -------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#sheetfilter">SheetFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>               | nil     | limit / offset / sort order options |

### Return Parameters

| Type                         | Description    |
| ---------------------------- | -------------- |
| [<a href="#sheet">Sheet</a>] | List of sheets |

## Get a specific Sheet by ID

```graphql
query Sheet($sheetId: ID!) {
  sheet(id: $sheetId) {
    sheet {
      id
      insertedAt
      isActive
      label
      lastSyncedAt
      updatedAt
      url
      sheetDataCount
    }
    errors {
      key
      message
    }
  }
}

{
  "sheetId": 1
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sheet": {
      "errors": null,
      "sheet": {
        "id": "1",
        "insertedAt": "2022-10-14T05:37:33.000000Z",
        "isActive": true,
        "label": "sheet1",
        "lastSyncedAt": "2022-10-14T05:37:32Z",
        "updatedAt": "2022-10-14T05:37:33.000000Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        "sheetDataCount": 4
      }
    }
  }
}
```

### Return Parameters

| Type                                   | Description   |
| -------------------------------------- | ------------- |
| <a href="#sheetresult">SheetResult</a> | Queried Sheet |

## Count all Sheets

```graphql
query countSheets($filter: SheetFilter) {
  countSheets(filter: $filter)
}

{
  "filter": {
    "name": "sheet"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countSheets": 2
  }
}
```

## Create a Sheet

```graphql

mutation ($input: SheetInput!) {
  createSheet(input: $input) {
    sheet {
      insertedAt
      id
      isActive
      label
      lastSyncedAt
      updatedAt
      url
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "label": "sheet1",
    "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createSheet": {
      "sheet": {
        "id": "3",
        "insertedAt": "2022-10-14T06:06:23.141322Z",
        "isActive": true,
        "label": "sheet1",
        "lastSyncedAt": "2022-10-14T06:06:23Z",
        "updatedAt": "2022-10-14T06:06:23.141322Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      },
      "errors": null
    }
  }
}
```

In case of sheet data error when media file exceeds WABA limit it will populate warning field

```graphql

mutation ($input: SheetInput!) {
  createSheet(input: $input) {
    sheet {
      insertedAt
      id
      isActive
      label
      lastSyncedAt
      updatedAt
      url
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "label": "sheet1",
    "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createSheet": {
      "sheet": {
        "id": "3",
        "insertedAt": "2022-10-14T06:06:23.141322Z",
        "isActive": true,
        "label": "sheet1",
        "lastSyncedAt": "2022-10-14T06:06:23Z",
        "updatedAt": "2022-10-14T06:06:23.141322Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0",
        "warnings": "{\"https://storage.googleapis.com/cc-tides/DSs2e3.mp4\":\"Size is too big for the video. Maximum size limit is 16384KB\"}"
      },
      "errors": null
    }
  }
}
```

In case of error while creating a new sheet, above functions return an error object like the below

```json
{
  "data": {
    "createSheet": {
      "errors": [
        {
          "key": "label",
          "message": "Label: can't be blank"
        }
      ],
      "sheet": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                 | Default  | Description |
| --------- | ------------------------------------ | -------- | ----------- |
| input     | <a href="#sheetinput">SheetInput</a> | required |             |

### Return Parameters

| Type                                   | Description              |
| -------------------------------------- | ------------------------ |
| <a href="#sheetresult">SheetResult</a> | The created sheet object |

## Update a Sheet

```graphql
mutation UpdateSheet($id: ID!, $input: SheetInput!) {
  updateSheet(id: $id, input: $input) {
    sheet {
      id
      isActive
      label
      lastSyncedAt
      updatedAt
      url
      insertedAt
    }
    errors {
      key
      message
    }
  }
}

{
  "id": 3,
  "input": {
    "label": "sheet3",
    "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateSheet": {
      "errors": null,
      "sheet": {
        "id": "3",
        "insertedAt": "2022-10-14T06:06:23.000000Z",
        "isActive": true,
        "label": "sheet3",
        "lastSyncedAt": "2022-10-14T06:10:57Z",
        "updatedAt": "2022-10-14T06:10:57.790150Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      }
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "updateSheet": {
      "errors": [
        {
          "key": "label",
          "message": "Label: can't be blank"
        }
      ],
      "sheet": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                 | Default  | Description |
| --------- | ------------------------------------ | -------- | ----------- |
| id        | <a href="#id">ID</a>!                | required |             |
| input     | <a href="#sheetinput">SheetInput</a> | required |             |

### Return Parameters

| Type                                   | Description              |
| -------------------------------------- | ------------------------ |
| <a href="#sheetresult">SheetResult</a> | The updated sheet object |

## Sync a Sheet

```graphql
mutation SyncSheet($syncSheetId: ID!) {
  syncSheet(id: $syncSheetId) {
    sheet {
      id
      isActive
      label
      lastSyncedAt
      updatedAt
      url
      insertedAt
    }
    errors {
      key
      message
    }
  }
}

{
  "id": 3
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "syncSheet": {
      "sheet": {
        "id": "3",
        "insertedAt": "2022-10-14T06:06:23.000000Z",
        "isActive": true,
        "label": "sheet3",
        "lastSyncedAt": "2022-10-14T06:10:57Z",
        "updatedAt": "2022-10-14T06:10:57.790150Z",
        "url": "https://docs.google.com/spreadsheets/d/1fRpFyicqrUFxd79u_dGC8UOHEtAT3rA-G2i4tvOgScw/edit#gid=0"
      },
      "errors": null
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "syncSheet": {
      "errors": [
        {
          "key": "Elixir.Glific.Sheets.Sheet",
          "message": "Resource not found"
        }
      ],
      "sheet": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                   | Description              |
| -------------------------------------- | ------------------------ |
| <a href="#sheetresult">SheetResult</a> | The updated sheet object |

## Delete a Sheet

```graphql
mutation DeleteSheet($id: ID!) {
  deleteSheet(id: $id) {
    errors {
      message
      key
    }
    sheet {
      insertedAt
      isActive
      label
      lastSyncedAt
      updatedAt
      rowData
      url
      id
    }
  }
}

{
  "id": "3"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteSheet": {
      "errors": null,
      "sheet": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteSheet": {
      "errors": [
        {
          "key": "Elixir.Glific.Sheets.Sheet",
          "message": "Resource not found"
        }
      ],
      "sheet": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                   | Description              |
| -------------------------------------- | ------------------------ |
| <a href="#sheetresult">SheetResult</a> | An error object or empty |

## Sheet Objects

### Sheet

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
<td colspan="2" valign="top"><strong>sheetType</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>lastSyncedAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>sheetDataCount</strong></td>
<td valign="top"><a href="#int">Int</a></td>
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

### SheetResult

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
<td colspan="2" valign="top"><strong>sheet</strong></td>
<td valign="top"><a href="#sheet">Sheet</a></td>
<td></td>
</tr>
</tbody>
</table>

### SheetInput

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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

### SheetFilter

Filtering options for sheets

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
  <td colspan="2" valign="top"><strong>label</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the sheet name</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>Match the isActive flag of sheet</td>
</tr>
</tbody>
</table>
