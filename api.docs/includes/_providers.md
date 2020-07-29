# Providers

## Get All Providers

```graphql
query providers($filter: ProviderFilter, $opts: Opts) {
  providers(filter: $filter, opts: $opts) {
    id
    name
    apiEndPoint
    url
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
        "apiEndPoint": "test",
        "id": "1",
        "name": "Default Provider",
        "url": "test_url"
      }
    ]
  }
}
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
      apiEndPoint
      url
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
        "apiEndPoint": "test",
        "id": "1",
        "name": "Default Provider",
        "url": "test_url"
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

## Create a Provider

```graphql
mutation createProvider($input:ProviderInput!) {
  createProvider(input: $input) {
    provider {
      id
      name
      apiEndPoint
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
    "name": "new_provider",
    "url": "new provider url",
    "apiEndPoint": "provider's api end point"
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
        "apiEndPoint": "provider's api end point",
        "id": "4",
        "name": "new_provider",
        "url": "new provider url"
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
      url
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
    "url": "updated url"
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
        "name": "Default Provider",
        "url": "updated url"
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
<td colspan="2" valign="top"><strong>apiEndPoint</strong></td>
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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the url of provider

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
<td colspan="2" valign="top"><strong>apiEndPoint</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>
