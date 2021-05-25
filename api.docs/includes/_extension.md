# Extensions

## Get Extension by ID

```graphql
query Extension(id: ID!) {
  Extension(id: $id) {
    code
    id
    insertedAt
    updatedAt
    isActive
    isValid
    module
    name
    organization {
    name
    isActive
    }
  }
}

{
  "id": 2
  "clientId": 2
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "Extension": {
      "Extension": {
        "code": "defmodule URI, do: def default_port(), do: %{hello: \"hello2”}",
        "id": "7",
        "insertedAt": "2021-05-19T11:47:30Z",
        "updatedAt": "2021-05-19T11:47:30Z",
        "isActive": false,
        "isValid": false,
        "module": null,
        "name": "URI",
        "organization": {
          "isActive": true,
          "name": "Glific"
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

## Get Organization Extension

```graphql
query Extension(client_id: ID!) {
  Extension(client_id: $client_id) {
    code
    id
    insertedAt
    updatedAt
    isActive
    isValid
    module
    name
    organization {
    name
    isActive
    }
  }
}

{
  "clientId": 2
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "Extension": {
      "Extension": {
        "code": "defmodule URI, do: def default_port(), do: %{hello: \"hello2”}",
        "id": "7",
        "insertedAt": "2021-05-19T11:47:30Z",
        "updatedAt": "2021-05-19T11:47:30Z",
        "isActive": false,
        "isValid": false,
        "module": null,
        "name": "URI",
        "organization": {
          "isActive": true,
          "name": "Glific"
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
| client_id | <a href="#id">ID</a> | nil     |             |

### Return Parameters

| Type                                            | Description                  |
| ----------------------------------------------- | ---------------------------- |
| <a href="#extension_result">ExtensionResult</a> | The queried extension object |

## Create a Extension

```graphql
mutation createExtension($input:ExtensionInput!) {
  createExtension(input: $input) {
    extension {
      code
      isActive
      name
      clientId
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
    "code": "defmodule URI, do: def default_port(), do: %{phone: 9876543210}",
    "isActive": true,
    "name": "URI"
  }
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createExtension": {
      "extension": {
        "code": "defmodule URI, do: def default_port(), do: %{phone: 9876543210}",
        "id": "7",
        "insertedAt": "2021-05-19T11:47:30Z",
        "updatedAt": "2021-05-19T11:47:30Z",
        "isActive": false,
        "isValid": false,
        "module": null,
        "name": "URI",
        "organization": {
          "isActive": true,
          "name": "Glific"
        }
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                          | Default  | Description |
| --------- | --------------------------------------------- | -------- | ----------- |
| input     | <a href="#extension_input">ExtensionInput</a> | required |             |

### Return Parameters

| Type                                            | Description                  |
| ----------------------------------------------- | ---------------------------- |
| <a href="#extension_result">ExtensionResult</a> | The created Extension object |

## Update a Extension

```graphql
mutation updateExtension($id: ID!, $input:ExtensionInput!) {
  updateExtension(id: $id!, input: $input) {
    Extension {
      code
      id
      insertedAt
      updatedAt
      isActive
      isValid
      module
      name
      organization {
        name
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
    "client_id": "1",
    "input": {
        "code": "defmodule URI, do: def default_port(), do: %{phone: 9997543210}"
    }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateExtension": {
      "Extension": {
        "code": "defmodule URI, do: def default_port(), do: %{phone: 9997543210}",
        "id": "7",
        "insertedAt": "2021-05-19T11:47:30Z",
        "updatedAt": "2021-05-19T11:47:30Z",
        "isActive": false,
        "isValid": false,
        "module": "Elixir.Glific.URI",
        "name": "URI",
        "organization": {
          "isActive": true,
          "name": "Glific"
        }
      },
      "errors": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                                          | Default  | Description |
| --------- | --------------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                         | required |             |
| input     | <a href="#extension_input">ExtensionInput</a> | required |             |

### Return Parameters

| Type                                            | Description                  |
| ----------------------------------------------- | ---------------------------- |
| <a href="#extension_result">ExtensionResult</a> | The created Extension object |

## Delete a Extension

```graphql
mutation  deleteExtension($id: ID!) {
   deleteExtension(id: $id!) {
    Extension {
      code
      id
      insertedAt
      updatedAt
      isActive
      isValid
      module
      name
      organization {
        name
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
    "id": "2"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    " deleteExtension": {
      "Extension": {
        "code": "defmodule URI, do: def default_port(), do: %{phone: 9876543210}",
        "id": "7",
        "insertedAt": "2021-05-19T11:47:30Z",
        "updatedAt": "2021-05-19T11:47:30Z",
        "isActive": false,
        "isValid": false,
        "module": null,
        "name": "URI",
        "organization": {
          "isActive": true,
          "name": "Glific"
        }
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

| Type                                            | Description                  |
| ----------------------------------------------- | ---------------------------- |
| <a href="#extension_result">ExtensionResult</a> | The created Extension object |

## Extension Objects

### Extension

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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>code</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>module</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_valid</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_active</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<td colspan="2" valign="top"><strong>organization</strong></td>
<td valign="top"><a href="#organization">Organization</a></td>
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

### ExtensionInput

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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>code</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_active</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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

### ExtensionResult

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
<td colspan="2" valign="top"><strong>extension</strong></td>
<td valign="top"><a href="#extension">Extension</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>
