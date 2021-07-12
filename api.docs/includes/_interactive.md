# Interactive

## Get All InteractiveTemplates

```graphql
query interactiveTemplates($filter: InteractiveTemplateFilter, $opts: Opts) {
  interactiveTemplates(filter: $filter, opts:$opts) {
    id
    insertedAt
    interactiveContent
    label
    type
    updatedAt
  }
}

{
  "filter": {
    "label": "news",
    "type": "QUICK_REPLY"
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
    "interactiveTemplates": [
      {
        "id": "1",
        "insertedAt": "2021-07-07T15:38:20.000000Z",
        "interactiveContent": "{\"type\":\"quick_reply\",\"options\":[{\"type\":\"text\",\"title\":\"Good\"},{\"type\":\"text\",\"title\":\"Not well\"},{\"type\":\"text\",\"title\":\"Sick\"}],\"content\":{\"type\":\"text\",\"text\":\"Hi John, how are you?\"}}",
        "label": "news",
        "type": "QUICK_REPLY",
        "updatedAt": "2021-07-07T15:38:20.000000Z"
      },
      {
        "id": "12",
        "insertedAt": "2021-07-07T15:38:20.000000Z",
        "interactiveContent": "{\"type\":\"quick_reply\",\"options\":[{\"type\":\"text\",\"title\":\"London\"},{\"type\":\"text\",\"title\":\"Berlin\"},{\"type\":\"text\",\"title\":\"Paris\"}],\"content\":{\"type\":\"text\",\"text\":\"Where have you been?\"}}",
        "label": "news2",
        "type": "QUICK_REPLY",
        "updatedAt": "2021-07-07T15:38:20.000000Z"
      }
    ]
  }
}
```

This returns all the Interactive Templates filtered by the input <a href="#InteractiveTemplateFilter">InteractiveTemplateFilter</a>

### Query Parameters

| Parameter | Type                                               | Default | Description                         |
| --------- | -------------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#InteractiveTemplateFilter">InteractiveTemplateFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                           | nil     | limit / offset / sort order options |

### Return Parameters

| Type                                     | Description          |
| ---------------------------------------- | -------------------- |
| [<a href="#interactiveTemplate">interactiveTemplate</a>] | List of InteractiveTemplates |

## Get a specific interactiveTemplate by ID

```graphql
query interactiveTemplate($id: ID!) {
  interactiveTemplate(id: $id) {
    interactiveTemplate {
        id
        insertedAt
        interactiveContent
        label
        type
        updatedAt
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
    "interactiveTemplate": {
      "interactiveTemplate": {
        "id": "12",
        "insertedAt": "2021-07-07T15:38:20.000000Z",
        "interactiveContent": "{\"type\":\"quick_reply\",\"options\":[{\"type\":\"text\",\"title\":\"London\"},{\"type\":\"text\",\"title\":\"Berlin\"},{\"type\":\"text\",\"title\":\"Paris\"}],\"content\":{\"type\":\"text\",\"text\":\"Where have you been?\"}}",
        "label": "news2",
        "type": "QUICK_REPLY",
        "updatedAt": "2021-07-07T15:38:20.000000Z"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                                               | Default | Description     |
| --------- | -------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#InteractiveTemplateFilter">InteractiveTemplateFilter</a> | nil     | filter the list |

### Return Parameters

| Type                                               | Description         |
| -------------------------------------------------- | ------------------- |
| <a href="#interactiveTemplateresult">interactiveTemplateResult</a> | Queried interactiveTemplate |

## Count all InteractiveTemplates

```graphql
query countInteractiveTemplates($filter: InteractiveTemplateFilter) {
  countInteractiveTemplates(filter: $filter)
}

{
  "filter":  {
    "type": "QUICK_REPLY"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countInteractiveTemplates": 15
  }
}
```

### Query Parameters

| Parameter | Type                                               | Default | Description     |
| --------- | -------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#InteractiveTemplateFilter">InteractiveTemplateFilter</a> | nil     | filter the list |

### Return Parameters

| Type                   | Description                    |
| ---------------------- | ------------------------------ |
| <a href="#int">Int</a> | Count of filtered InteractiveTemplates |

## Create a InteractiveTemplate

```graphql
mutation createInteractiveTemplate($input:interactiveTemplateInput!) {
  createInteractiveTemplate(input: $input) {
    interactiveTemplate {
      type
      label
      interactiveContent
    }
    errors{
            key
      message
    }
  }
}

{
  "input": {
    "type": "QUICK_REPLY",
    "label": "news2",
    "interactiveContent": {"type": "quick_reply", "content": {"text": "Hi John, how are you?", "type": "text"}, "options": [{"type": "text", "title": "First"}, {"type": "text", "title": "Second"}, {"type": "text", "title": "Third"}]}
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createInteractiveTemplate": {
      "errors": null,
      "interactive": {
        "id": "2",
        "insertedAt": "2021-07-07T10:19:00.887484Z",
        "interactiveContent": "{\"type\":\"quick_reply\",\"options\":[{\"type\":\"text\",\"title\":\"First\"},{\"type\":\"text\",\"title\":\"Second\"},{\"type\":\"text\",\"title\":\"Third\"}],\"content\":{\"type\":\"text\",\"text\":\"Hi John, how are you?\"}}",
        "label": "news2",
        "type": "QUICK_REPLY",
        "updatedAt": "2021-07-07T10:19:00.887484Z"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                                             | Default  | Description |
| --------- | ------------------------------------------------ | -------- | ----------- |
| input     | <a href="#interactiveTemplateinput">interactiveTemplateInput</a> | required |             |

### Return Parameters

| Type                                               | Description                    |
| -------------------------------------------------- | ------------------------------ |
| <a href="#interactiveTemplateresult">interactiveTemplateResult</a> | The created Interactive object |

## Update a interactiveTemplate

```graphql
mutation updateInteractiveTemplate($id: ID!, $input:interactiveTemplateInput!) {
  updateInteractiveTemplate(id: $id, input: $input) {
    interactive {
      insertedAt
      interactiveContent
      label
      type
      updatedAt
      id
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
    "label": "all weather"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateinteractiveTemplate": {
      "errors": null,
      "interactive": {
        "id": "2",
        "insertedAt": "2021-07-07T10:19:01.000000Z",
        "interactiveContent": "{\"type\":\"quick_reply\",\"options\":[{\"type\":\"text\",\"title\":\"First\"},{\"type\":\"text\",\"title\":\"Second\"},{\"type\":\"text\",\"title\":\"Third\"}],\"content\":{\"type\":\"text\",\"text\":\"Hi John, how are you?\"}}",
        "label": "all weather",
        "type": "QUICK_REPLY",
        "updatedAt": "2021-07-07T10:24:27.000000Z"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                                             | Default  | Description |
| --------- | ------------------------------------------------ | -------- | ----------- |
| id        | <a href="#id">ID</a>!                            | required |             |
| input     | <a href="#interactiveTemplateinput">interactiveTemplateInput</a> | required |             |

### Return Parameters

| Type                                               | Description                    |
| -------------------------------------------------- | ------------------------------ |
| <a href="#interactiveTemplateresult">interactiveTemplateResult</a> | The updated Interactive object |

## Delete a interactiveTemplate

```graphql
mutation deleteInteractiveTemplate($id: ID!) {
  deleteInteractiveTemplate(id: $id) {
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
    "deleteinteractiveTemplate": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteinteractiveTemplate": {
      "errors": [
        {
          "key": "Elixir.Glific.Templates.InterativeTemplate",
          "message": "Resource not found"
        }
      ]
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                               | Description              |
| -------------------------------------------------- | ------------------------ |
| <a href="#interactiveTemplateresult">interactiveTemplateResult</a> | An error object or empty |

## InteractiveTemplate Objects

### interactiveTemplate

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
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#interactive_message_type_enum">InteractiveMessageType</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>interactive_content</strong></td>
<td valign="top"><a href="#json">Json</a></td>
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

### interactiveTemplateResult

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
<td colspan="2" valign="top"><strong>interactiveTemplate</strong></td>
<td valign="top"><a href="#interactiveTemplate">interactiveTemplate</a></td>
<td></td>
</tr>
</tbody>
</table>

## InteractiveTemplate Inputs

### InteractiveTemplateFilter

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
<td colspan="2" valign="top"><strong>label</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match term with label interactive message

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#interactive_message_type_enum">InteractiveMessageType</a></td>
<td>

Match the type of interactive message

</tbody>
</table>

### interactiveTemplateInput

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
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#interactive_message_type_enum">InteractiveMessageType</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>interactive_content</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
</tbody>
</table>
