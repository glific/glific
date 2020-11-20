# Providers

## Get All Providers

```graphql
query providers($filter: ProviderFilter, $opts: Opts) {
  providers(filter: $filter, opts: $opts) {
    id
    name
    shortcode
    keys
    secrets
    group
    description
    isRequired
  }
}

{
  "opts": {
    "limit": 10,
    "offset": 1,
    "order": "ASC"
  },
  "filter": {
    "name": "Default"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "providers": [
      {
        "id": "3",
        "keys": "{}",
        "name": "Dialogflow",
        "secrets": "{}",
        "shortcode": "dialogflow",
        "group": null,
        "description": "Provider for Dialogflow"
      },
      {
        "id": "2",
        "keys": "{}",
        "name": "Gupshup",
        "secrets": "{}",
        "shortcode": "gupshup",
        "group": "bsp",
        "description": "BSP provider"
      }
    ]
```
This returns all the providers filtered by the input <a href="#providerfilter">ProviderFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#providerfilter">ProviderFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#provider">Provider</a>] | List of providers

## Get a specific Provider by ID

```graphql
query provider($id: ID!) {
  provider(id: $id) {
    provider {
      id
      name
      shortcode
      keys
      secrets
      group
      isRequired
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
    "provider": {
      "provider": {
        "group": "bsp",
        "id": "1",
        "isRequired": true,
        "keys": "{}",
        "name": "Gupshup",
        "secrets": "{}",
        "shortcode": "gupshup"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#providerfilter">ProviderFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#providerresult">ProviderResult</a> | Queried Provider

## Count all Providers

```graphql
query countProviders($filter: ProviderFilter) {
  countProviders(filter: $filter)
}

{
  "filter": {
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countProviders": 3
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#providerfilter">ProviderFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of filtered providers

## Get BSP balance for an organization

```graphql
query bspbalance {
  bspbalance {
    key
    value
  }
}

```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "bspbalance": {
      "key": "bsp_balance",
      "value": "{\"balance\":0.628}"
    }
  }
}
```

### Return Parameters
Type | Description
| ---- | -----------
<a href="#bsp_balance_result">bsp_balance_result</a> | remaining bsp balance

## Create a Provider

```graphql
mutation createProvider($input:ProviderInput!) {
  createProvider(input: $input) {
    provider {
      id
      name
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "name": "new_provider",
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createProvider": {
      "errors": null,
      "provider": {
        "id": "4",
        "name": "new_provider",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#providerinput">ProviderInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#providerresult">ProviderResult</a> | The created provider object

## Update a Provider

```graphql
mutation updateProvider($id: ID!, $input:ProviderInput!) {
  updateProvider(id: $id, input: $input) {
    provider {
      id
      name
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "1",
  "input": {
    "name": "Updated Provider",
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateProvider": {
      "errors": null,
      "provider": {
        "id": "1",
        "name": "Updated Provider",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#providerinput">ProviderInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#providerresult">ProviderResult</a> | The updated provider object


## Delete a Provider

```graphql
mutation deleteProvider($id: ID!) {
  deleteProvider(id: $id) {
    provider {
      id
      name
    }
    errors {
      key
      message
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
    "deleteProvider": {
      "errors": null,
      "provider": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteProvider": {
      "errors": [
        {
          "key": "Elixir.Glific.Partners.Provider 3",
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
<a href="#providerresult">ProviderResult</a> | An error object or empty

## Provider Objects

### Provider

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
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
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
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isRequired</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keys</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td>structure for keys</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>secrets</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td>structure for secrets</td>
</tr>
</tbody>
</table>

### Bsp Balance

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
<td colspan="2" valign="top"><strong>key</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#id">Json</a></td>
<td></td>
</tr>
</tbody>
</table>

### ProviderResult

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
<td colspan="2" valign="top"><strong>provider</strong></td>
<td valign="top"><a href="#provider">Provider</a></td>
<td></td>
</tr>
</tbody>
</table>


## Provider Inputs ##

### ProviderFilter

Filtering options for providers

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
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the shortcode of provider

</td>
</tr>
</tbody>
</table>

### ProviderInput

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
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>description</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isRequired</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keys</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td>structure for keys</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>secrets</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td>structure for secrets</td>
</tr>
</tbody>
</table>
