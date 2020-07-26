# Saved Searches

## Get All Saved Searches

```graphql
query savedSearches($filter: SavedSearchFilters!) {
  savedSearches(filter: $filter) {
    id
    label
    shortcode
    args
  }
}

{
  "filter": {
    "label": "Unread"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "savedSearches": [
      {
        "args": "{
          \"term\":\"\",
          \"messageOpts\":{\"limit\":5},
          \"filter\":{\"includeTags\":[\"10\"]},
          \"contactOpts\":{\"limit\":10}
        }",
        "id": "1",
        "label": "All unread conversations",
        "shortcode": "Unread"
      }
    ]
  }
}
```
This returns all the saved searches for the organization filtered by the input <a href="#savedsearchfilters">SavedSearchFilters</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#savedsearchfilters">SavedSearchFilters</a> | nil | filter the list

## Get a specific Saved Search by ID

```graphql
query savedSearch($id: ID!) {
  savedSearch(id: $id) {
    savedSearch {
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
    "savedSearch": {
      "savedSearch": {
        "id": "2",
        "label": "All Read and Not replied messages",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a>


## Save a Search

```graphql
mutation createSavedSearch($input: SavedSearchInput!) {
  createSavedSearch(input: $input) {
    savedSearch {
      id
      label
      shortcode
      args
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "label": "This is a saved search",
    "shortcode": "Save Search"
    "args": "{"term": "\Save this search\"}"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "savedSearch": {
      "errors": null,
      "savedSearch": {
        "id": "26",
        "label": "This is a saved search",
        "shortcode": "Save Search",
        "args": "{\"term\": \"Save this search\"}",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#savesearchinput">SaveSearchInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#savedsearchresult">SavedSearchResult</a> | The created Saved Search object

## Update a Saved Search

```graphql
mutation updateSavedSearch($id: ID!, $input:SavedSearchInput!) {
  updateSavedSearch(id: $id, input: $input) {
    savedSearch {
      id
      label
    }
    errors {
      key
      message
    }
  }
}

{
  "id": "26",
  "input": {
    "label": "This is a updated saved search",
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateSavedSearch": {
      "errors": null,
      "savedSearch": {
        "id": "26",
        "label": "This is a updated saved search",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#savedsearchinput">SavedSearchInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#savedsearchresult">SavedSearchResult</a> | The updated saved search object


## Delete a SavedSearch

```graphql
mutation deleteSavedSearch($id: ID!) {
  deleteSavedSearch(id: $id) {
    errors {
      key
      message
    }
  }
}

{
  "id": "26"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteSavedSearch": {
      "errors": null,
      "savedSearch": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteSavedSearch": {
      "errors": [
        {
          "key": "Elixir.Glific.Searches.SavedSearch 26",
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
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#savedsearchresult">SavedSearchResult</a> | An error object or empty


## Saved Search Objects

### SavedSearch

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
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>Args</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
</tbody>
</table>

### SavedSearchResult ###

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
<td colspan="2" valign="top"><strong>SavedSearch</strong></td>
<td valign="top"><a href="#savedsearch">SavedSearch</a></td>
<td></td>
</tr>
</tbody>
</table>

## SavedSearch Inputs ##


### SavedSearchFilter ###

Filtering options for savedSearches

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
<td>Match the label</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the shortcode</td>
</tr>
</tbody>
</table>

### SavedSearchInput ###

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
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>Args</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
</tbody>
</table>
