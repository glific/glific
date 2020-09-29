# Credentials

## Get a specific Credential by provider/service shortcode

```graphql
query credential($shortcode: String!) {
  credential(shortcode: $shortcode) {
    credential {
      id
      keys
      secrets
      provider {
        shortcode
      }
    }
  }
}

{
  "shortcode": "gupshup"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "credential": {
      "credential": {
        "id": "1",
        "keys": "{\"worker\":\"Glific.Providers.Gupshup.Worker\",\"url\":\"https://gupshup.io/\",\"handler\":\"Glific.Providers.Gupshup.Message\",\"api_end_point\":\"https://api.gupshup.io/sm/api/v1\"}",
        "provider": {
          "shortcode": "gupshup"
        },
        "secrets": "{\"app_name\":\"Please enter your App Name here\",\"api_key\":\"Please enter your key here\"}"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
shortcode | <a href="#string">String</a> ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#credentialresult">CredentialResult</a> | Queried Credential

## Create a Credential

```graphql
mutation createCredential($input: CredentialInput!) {
  createCredential(input: $input) {
    credential {
      keys
      secrets
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "shortcode": "shortcode",
    "secrets": "{\"app_name\":\"App Name\",\"api_key\":\"App Key\"}"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createCredential": {
      "credential": {
        "keys": null,
        "secrets": "{\"app_name\":\"App Name\",\"api_key\":\"App Key\"}"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#credentialinput">CredentialInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#credentialresult">CredentialResult</a> | The created credential object

## Update a Credential

```graphql
mutation updateCredential($id: ID!, $input: CredentialInput!) {
  updateCredential(id: $id, input: $input) {
    credential {
      id
      provider {
        shortcode
      }
      keys
      secrets
    }
    errors {
      key
      message
    }
  }
}

{
  "id": 1,
  "input": {
    "secrets": "{\"app_name\":\"updated App Name\",\"api_key\":\"updated app key\"}"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateCredential": {
      "credential": {
        "id": "1",
        "keys": "{\"worker\":\"Glific.Providers.Gupshup.Worker\",\"url\":\"https://gupshup.io/\",\"handler\":\"Glific.Providers.Gupshup.Message\",\"api_end_point\":\"https://api.gupshup.io/sm/api/v1\"}",
        "provider": {
          "shortcode": "gupshup"
        },
        "secrets": "{\"app_name\":\"updated App Name\",\"api_key\":\"updated app key\"}"
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
input | <a href="#credentialinput">CredentialInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#credentialresult">CredentialResult</a> | The updated credential object


## Credential Objects

### Credential

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
<td colspan="2" valign="top"><strong>keys</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>secrets</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>provider</strong></td>
<td valign="top"><a href="#provider">Provider</a></td>
<td></td>
</tr>
</tbody>
</table>

### CredentialResult

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
<td colspan="2" valign="top"><strong>credential</strong></td>
<td valign="top"><a href="#credential">Credential</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## Credential Inputs ##

### CredentialInput

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
<td colspan="2" valign="top"><strong>keys</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>secrets</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>
