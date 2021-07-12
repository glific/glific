# Interactive

## Get All Interactives

```graphql
query interactives($filter: InteractiveFilter, $opts: Opts) {
  interactives(filter: $filter, opts:$opts) {
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
    "interactives": [
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

This returns all the Interactives filtered by the input <a href="#InteractiveFilter">InteractiveFilter</a>

### Query Parameters

| Parameter | Type                                               | Default | Description                         |
| --------- | -------------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#InteractiveFilter">InteractiveFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                           | nil     | limit / offset / sort order options |

### Return Parameters

| Type                                     | Description          |
| ---------------------------------------- | -------------------- |
| [<a href="#interactive">interactive</a>] | List of Interactives |

## Get a specific interactive by ID

```graphql
query interactive($id: ID!) {
  interactive(id: $id) {
    interactive {
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
    "interactive": {
      "interactive": {
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
| filter    | <a href="#InteractiveFilter">InteractiveFilter</a> | nil     | filter the list |

### Return Parameters

| Type                                               | Description         |
| -------------------------------------------------- | ------------------- |
| <a href="#interactiveresult">interactiveResult</a> | Queried interactive |

## Count all Interactives

```graphql
query countInteractives($filter: InteractiveFilter) {
  countInteractives(filter: $filter)
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
    "countInteractives": 15
  }
}
```

### Query Parameters

| Parameter | Type                                               | Default | Description     |
| --------- | -------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#InteractiveFilter">InteractiveFilter</a> | nil     | filter the list |

### Return Parameters

| Type                   | Description                    |
| ---------------------- | ------------------------------ |
| <a href="#int">Int</a> | Count of filtered Interactives |

## Create a Interactive

```graphql
mutation createInteractive($input:interactiveInput!) {
  createInteractive(input: $input) {
    interactive {
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
    "createInteractive": {
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
| input     | <a href="#interactiveinput">interactiveInput</a> | required |             |

### Return Parameters

| Type                                               | Description                    |
| -------------------------------------------------- | ------------------------------ |
| <a href="#interactiveresult">interactiveResult</a> | The created Interactive object |

## Update a interactive

```graphql
mutation updateInteractive($id: ID!, $input:interactiveInput!) {
  updateInteractive(id: $id, input: $input) {
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
    "updateinteractive": {
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
| input     | <a href="#interactiveinput">interactiveInput</a> | required |             |

### Return Parameters

| Type                                               | Description                    |
| -------------------------------------------------- | ------------------------------ |
| <a href="#interactiveresult">interactiveResult</a> | The updated Interactive object |

## Delete a interactive

```graphql
mutation deleteInteractive($id: ID!) {
  deleteInteractive(id: $id) {
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
    "deleteinteractive": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteinteractive": {
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
| <a href="#interactiveresult">interactiveResult</a> | An error object or empty |

## Interactive Objects

### interactive

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

### interactiveResult

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
<td colspan="2" valign="top"><strong>interactive</strong></td>
<td valign="top"><a href="#interactive">interactive</a></td>
<td></td>
</tr>
</tbody>
</table>

## Interactive Inputs

### InteractiveFilter

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

### interactiveInput

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
