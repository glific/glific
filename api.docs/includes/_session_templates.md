# Session Template

## Get All Session Templates

```graphql
query sessionTemplates($filter: SessionTemplateFilter, $opts: Opts) {
  sessionTemplates(filter: $filter, opts:$opts) {
    id
    body
    label
    shortcode
    isHsm
    type
    isActive
    isReserved
    isSource
    parent {
      id
      label
    }
    language {
      id
      label
    }
    messageMedia {
      id
      caption
    }
  }
}

{
  "filter": {
  	"body": "template",
    "term": "label"
  },
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sessionTemplates": [
      {
        "body": "Another Template",
        "id": "2",
        "isActive": false,
        "isHsm": false,
        "isReserved": false,
        "isSource": false,
        "label": "Another Template Label",
        "language": {
          "id": "2",
          "label": "English (United States)"
        },
        "messageMedia": null,
        "parent": {
          "id": "1",
          "label": "Default Template Label"
        },
        "shortcode": null,
        "type": "TEXT"
      },
      {
        "body": "Default Template",
        "id": "1",
        "isActive": false,
        "isHsm": false,
        "isReserved": false,
        "isSource": false,
        "label": "Default Template Label",
        "language": {
          "id": "2",
          "label": "English (United States)"
        },
        "messageMedia": null,
        "parent": null,
        "shortcode": null,
        "type": "TEXT"
      }
    ]
  }
}
```
This returns all the session templates filtered by the input <a href="#sessiontemplatefilter">SessionTemplateFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#sessiontemplatefilter">SessionTemplateFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#sessiontemplate">SessionTemplate</a>] | List of session templates

## Get a specific SessionTemplate by ID

```graphql
query sessionTemplate($id: ID!) {
  sessionTemplate(id: $id) {
    sessionTemplate {
      id
      body
      label
      shortcode
      type
      language {
        id
        label
      }
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
    "sessionTemplate": {
      "sessionTemplate": {
        "body": "Default Template",
        "id": "1",
        "label": "Default Template Label",
        "language": {
          "id": "2",
          "label": "English (United States)"
        },
        "shortcode": null,
        "type": "TEXT"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#sessiontemplatefilter">SessionTemplateFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#sessiontemplateresult">SessionTemplateResult</a> | Queried SessionTemplate

## Count all Session Templates

```graphql
query countSessionTemplates($filter: SessionTemplateFilter) {
  countSessionTemplates(filter: $filter)
}

{
  "filter":  {
    "language": "Hindi"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countSessionTemplates": 15
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#sessiontemplatefilter">SessionTemplateFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of filtered session templates

## Create a Session Template

```graphql
mutation createSessionTemplate($input:SessionTemplateInput!) {
  createSessionTemplate(input: $input) {
    sessionTemplate {
      id
      body
      label
      shortcode
      type
    }
    errors{
			key
      message
    }
  }
}

{
  "input": {
    "body": "Test template",
    "label": "Test label",
    "languageId": 1,
    "type": "TEXT"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createSessionTemplate": {
      "errors": null,
      "sessionTemplate": {
        "body": "Test template",
        "id": "34",
        "label": "Test label",
        "shortcode": null,
        "type": "TEXT"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#sessiontemplateinput">SessionTemplateInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#sessiontemplateresult">SessionTemplateResult</a> | The created session template object

## Update a SessionTemplate

```graphql
mutation updateSessionTemplate($id: ID!, $input:SessionTemplateInput!) {
  updateSessionTemplate(id: $id, input: $input) {
    sessionTemplate {
      id
      body
      label
      shortcode
      type
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
    "body": "Test template"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateSessionTemplate": {
      "errors": null,
      "sessionTemplate": {
        "body": "Test template",
        "id": "1",
        "label": "Default Template Label",
        "shortcode": null,
        "type": "TEXT"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#sessiontemplateinput">SessionTemplateInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#sessiontemplateresult">SessionTemplateResult</a> | The updated session template object


## Delete a SessionTemplate

```graphql
mutation deleteSessionTemplate($id: ID!) {
  deleteSessionTemplate(id: $id) {
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
    "deleteSessionTemplate": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteSessionTemplate": {
      "errors": [
        {
          "key": "Elixir.Glific.Templates.SessionTemplate 3",
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
<a href="#sessiontemplateresult">SessionTemplateResult</a> | An error object or empty

## Session Template Objects

### SessionTemplate

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
<td colspan="2" valign="top"><strong>body</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
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
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isSource</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>messageMedia</strong></td>
<td valign="top"><a href="#messagemedia">MessageMedia</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parent</strong></td>
<td valign="top"><a href="#sessiontemplate">SessionTemplate</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#messagetypesenum">MessageTypesEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isHsm</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>number_parameters</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td></td>
</tr>
</tbody>
</table>

### SessionTemplateResult

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
<td colspan="2" valign="top"><strong>sessionTemplate</strong></td>
<td valign="top"><a href="#sessiontemplate">SessionTemplate</a></td>
<td></td>
</tr>
</tbody>
</table>


## Session Template Inputs ##

### SessionTemplateFilter

Filtering options for session_templates

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
<td colspan="2" valign="top"><strong>term</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match term with labe/body/shortcode of template or label/shortcode of associated tag

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>body</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the body of template

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>

Match the active flag

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isReserved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>

Match the reserved flag

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the label

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>language</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match a language

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>languageId</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td>

Match a language id

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parent</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the parent

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>parentId</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td>

Match the parent

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the shortcode of template

</td>
</tr>

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>is_hsm</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>

Match the hsm template message

</td>
</tr>

</tbody>
</table>

### SessionTemplateInput

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
<td colspan="2" valign="top"><strong>body</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isSource</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isHsm</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>number_parameters</strong></td>
<td valign="top"><a href="#int">Int</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>languageId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>shortcode</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#messagetypesenum">MessageTypesEnum</a></td>
<td></td>
</tr>
</tbody>
</table>
