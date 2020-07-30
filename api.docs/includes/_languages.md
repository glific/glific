# Languages

## Get All Languages

```graphql
query languages($opts: Opts) {
  languages(opts: $opts){
    id
    label
    labelLocale
    locale
    isActive
  }
}

{
  "opts": {
    "order": "DESC",
    "limit": 10,
    "offset": 0
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "languages": [
      {
        "id": "1",
        "isActive": false,
        "label": "Hindi",
        "labelLocale": "हिंदी",
        "locale": "hi"
      },
      {
        "id": "2",
        "isActive": false,
        "label": "English (United States)",
        "labelLocale": "English",
        "locale": "en_US"
      }
    ]
  }
}
```
This returns all the languages filtered by the input <a href="#languagefilter">LanguageFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#languagefilter">LanguageFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#language">Language</a>] | List of languages

## Get a specific language by ID

```graphql
query language($id: ID!) {
  language(id: $id) {
    language {
      id
      label
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
    "language": {
      "language": {
        "id": "2",
        "label": "English (United States)"
      }
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
| ---- | -----------
<a href="#languageresult">LanguageResult</a> | Queried Language

## Count all Languages

```graphql
query countLanguages {
  countLanguages
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countLanguages": 2
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#languagefilter">LanguageFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of languages

## Create a Lanuguage

```graphql
mutation createLanguage($input:LanguageInput!) {
  createLanguage(input: $input) {
    language {
      id
      label
      labelLocale
      locale
      isActive
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "label": "Kannada",
    "isActive": true,
    "locale": "kn",
    "labelLocale": "Kannada"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createLanguage": {
      "errors": null,
      "language": {
        "id": "3",
        "isActive": true,
        "label": "Kannada",
        "labelLocale": "Kannada",
        "locale": "kn"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#languageinput">LanguageInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#languageresult">LanguageResult</a> | The created language object

## Update a Language

```graphql
mutation updateLanguage($id: ID!, $input: LanguageInput!) {
  updateLanguage(id: $id, input: $input) {
    language {
      id
      label
      labelLocale
      locale
      isActive
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
    "label": "Kannada",
    "isActive": false,
    "locale": "kn",
    "labelLocale": "Kannada"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateLanguage": {
      "errors": null,
      "language": {
        "id": "3",
        "isActive": false,
        "label": "Kannada",
        "labelLocale": "Kannada",
        "locale": "kn"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#languageinput">LanguageInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#languageresult">LanguageResult</a> | The updated language object


## Delete a Language

```graphql
mutation deleteLanguage($id: ID!) {
  deleteLanguage(id: $id) {
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
    "deleteLanguage": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteLanguage": {
      "errors": [
        {
          "key": "Elixir.Glific.Settings.Language 3",
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
<a href="#languageresult">LanguageResult</a> | An error object or empty

## Language Objects

### Language

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
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>labelLocale</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>locale</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### LanguageResult

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
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
</tbody>
</table>

## Language Inputs ##

### LanguageInput

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
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a>!</td>
<td>

Unique

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>labelLocale</strong></td>
<td valign="top"><a href="#string">String</a>!</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>locale</strong></td>
<td valign="top"><a href="#string">String</a>!</td>
<td></td>
</tr>
</tbody>
</table>
