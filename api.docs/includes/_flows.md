# Flows

## Get All Flows

```graphql
query flows($filter: FlowFilter, $opts: Opts) {
  flows(filter: $filter, opts: $opts) {
    id
    uuid
    name
    versionNumber
    flowType
    keywords
    lastPublishedAt
    lastChangedAt
  }
}

{
  "opts": {
    "limit": 2,
    "offset": 0,
    "order": "ASC"
  },
  "filter": {
    "name": "Workflow"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "flows": [
      {
        "flowType": "MESSAGE",
        "id": "1",
        "keywords": ["help", "मदद"],
        "name": "Help Workflow",
        "uuid": "3fa22108-f464-41e5-81d9-d8a298854429",
        "lastChangedAt": "2021-03-25T10:03:26Z",
        "lastPublishedAt": "2021-03-25T10:03:26Z",
        "versionNumber": "13.1.0"
      },
      {
        "flowType": "MESSAGE",
        "id": "2",
        "keywords": ["language"],
        "name": "Language Workflow",
        "uuid": "f5f0c89e-d5f6-4610-babf-ca0f12cbfcbf",
        "lastChangedAt": "2021-03-25T10:03:26Z",
        "lastPublishedAt": "2021-03-25T10:03:26Z",
        "versionNumber": "13.1.0"
      }
    ]
  }
}
```

This returns all the flows

### Query Parameters

| Parameter | Type                                 | Default | Description                         |
| --------- | ------------------------------------ | ------- | ----------------------------------- |
| filter    | <a href="#flowfilter">FlowFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>             | nil     | limit / offset / sort order options |

### Return Parameters

| Type                       | Description   |
| -------------------------- | ------------- |
| [<a href="#flow">Flow</a>] | List of flows |

## Get a specific Flow by ID

```graphql
query flow($id: ID!) {
  flow(id: $id) {
    flow {
      id
      name
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
    "flow": {
      "flow": {
        "id": "1",
        "name": "Help Workflow"
      }
    }
  }
}
```

### Return Parameters

| Type                                 | Description  |
| ------------------------------------ | ------------ |
| <a href="#flowresult">FlowResult</a> | Queried Flow |

## Count all Flows

```graphql
query countFlows($filter: FlowFilter) {
  countFlows(filter: $filter)
}

{
  "filter": {
    "name": "help"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countFlows": 2
  }
}
```

## Create a Flow

```graphql
mutation ($input: FlowInput!) {
  createFlow(input: $input) {
    flow {
      id
      name
      keywords
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
    "keywords": [
      "tests",
      "testing"
    ],
    "name": "test workflow",
    "isActive": true
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createFlow": {
      "errors": null,
      "flow": {
        "id": "12",
        "keywords": ["tests", "testing"],
        "name": "test workflow"
      }
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "createFlow": {
      "errors": [
        {
          "key": "name",
          "message": "can't be blank"
        }
      ],
      "flow": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                               | Default  | Description |
| --------- | ---------------------------------- | -------- | ----------- |
| input     | <a href="#flowinput">FlowInput</a> | required |             |

### Return Parameters

| Type                                 | Description             |
| ------------------------------------ | ----------------------- |
| <a href="#flowresult">FlowResult</a> | The created flow object |

## Update a Flow

```graphql
mutation updateFlow($id: ID!, $input:FlowInput!) {
  updateFlow(id: $id, input: $input) {
    flow {
      id
      name
      keywords
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
    "name": "updated name",
    "keywords": ["test", "testing"]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateFlow": {
      "errors": null,
      "flow": {
        "id": "1",
        "name": "updated name",
        "keywords": ["test", "testing"]
      }
    }
  }
}
```

In case of errors, above functions return an error object like the below

```json
{
  "data": {
    "updateFlow": {
      "errors": [
        {
          "key": "keywords",
          "message": "global keywords [test, testing] are already taken"
        }
      ],
      "flow": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                               | Default  | Description |
| --------- | ---------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!              | required |             |
| input     | <a href="#flowinput">FlowInput</a> | required |             |

### Return Parameters

| Type                                 | Description             |
| ------------------------------------ | ----------------------- |
| <a href="#flowresult">FlowResult</a> | The updated flow object |

## Delete a Flow

```graphql
mutation deleteFlow($id: ID!) {
  deleteFlow(id: $id) {
    flow {
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
    "deleteFlow": {
      "errors": null,
      "flow": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteFlow": {
      "errors": [
        {
          "key": "Elixir.Glific.Flows.Flow 3",
          "message": "Resource not found"
        }
      ],
      "flow": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                 | Description              |
| ------------------------------------ | ------------------------ |
| <a href="#flowresult">FlowResult</a> | An error object or empty |

## Publish a Flow

```graphql
mutation publishFlow($uuid: UUID4!) {
  publishFlow(uuid: $uuid) {
    success
    errors {
      key
      message
    }
  }
}

{
  "uuid": "3fa22108-f464-41e5-81d9-d8a298854429"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "publishFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "publishFlow": {
      "errors": [
        {
          "key": "Flow UUID: 9a2788e1-26cd-44d0-8868-d8f0552a08a6",
          "message": "Resource not found"
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                               | Description                      |
| -------------------------------------------------- | -------------------------------- |
| <a href="#flowresult">FlowResult</a> | An error object or response true |

## Start flow for a contact

```graphql
mutation startContactFlow($flowId: ID!, $contactId: ID!) {
  startContactFlow(flowId: $flowId, contactId: $contactId) {
    success
    errors {
        key
        message
    }
  }
}

{
  "flowId": "1",
  "contactId": "2"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "startContactFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "startContactFlow": {
      "errors": [
        {
          "key": "contact",
          "message": "Cannot send the message to the contact."
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| flowId    | <a href="#id">ID</a>! | required |             |
| contactId | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                           | Description                              |
| ---------------------------------------------- | ---------------------------------------- |
| <a href="#flowresult">FlowResult</a> | An error object or success response true |

## Resume flow for a contact

```graphql
mutation resumeContactFlow($flowId: ID!, $contactId: ID!, $result: JSON!) {
  resumeContactFlow(flowId: $flowId, contactId: $contactId, result: $result) {
    success
    errors {
        key
        message
    }
  }
}

{
  "flowId": "1",
  "contactId": "2"
  "result": {"one": 1, "two": 2, "three": 3}
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "startContactFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "startContactFlow": {
      "errors": [
        {
          "key": "contact",
          "message": "does not have any active flows awaiting results."
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| flowId    | <a href="#id">ID</a>! | required |             |
| contactId | <a href="#id">ID</a>! | required |             |
| result | <a href="#json">JSON</a>! | required |             |

### Return Parameters

| Type                                           | Description                              |
| ---------------------------------------------- | ---------------------------------------- |
| <a href="#flowresult">FlowResult</a> | An error object or success response true |

## Start flow for a group contacts

```graphql
mutation startGroupFlow($flowId: ID!, $groupId: ID!) {
  startGroupFlow(flowId: $flowId, groupId: $groupId) {
    success
    errors {
        key
        message
    }
  }
}

{
  "flowId": "1",
  "groupId": "1"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "startGroupFlow": {
      "errors": null,
      "success": true
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "startGroupFlow": {
      "errors": [
        {
          "key": "Elixir.Glific.Flows.Flow 11",
          "message": "Resource not found"
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| flowId    | <a href="#id">ID</a>! | required |             |
| groupId   | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                           | Description                              |
| ---------------------------------------------- | ---------------------------------------- |
| <a href="#flowresult">FlowResult</a> | An error object or success response true |

## Copy a Flow

```graphql
mutation copyFlow($id: ID!, $input:FlowInput!) {
  copyFlow(id: $id, input: $input) {
    flow {
      id
      name
      keywords
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
    "name": "new name"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "copyFlow": {
      "errors": null,
      "flow": {
        "id": "32",
        "keywords": [],
        "name": "new name"
      }
    }
  }
}
```

### Query Parameters

| Parameter | Type                               | Default  | Description |
| --------- | ---------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!              | required |             |
| input     | <a href="#flowinput">FlowInput</a> | required |             |

### Return Parameters

| Type                                 | Description            |
| ------------------------------------ | ---------------------- |
| <a href="#flowresult">FlowResult</a> | The copied flow object |

## Import a Flow

```graphql
mutation ($flow: JSON!) {
  importFlow(flow: $flow){
    success
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "{\"flows\":[{\"keywords\":[\"hello\"],\"definition\":{\"vars\":[\"a941004f-adc8-43f2-b819-68eec8d1e912\"],\"uuid\":\"a941004f-adc8-43f2-b819-68eec8d1e912\",\"type\":\"messaging\",\"spec_version\":\"13.1.0\",\"revision\":1,\"nodes\":[{\"uuid\":\"59c67035-59ab-47fa-a1fd-a50978aa78c5\",\"exits\":[{\"uuid\":\"49d2775d-a658-4c74-be10-b7d605b4ea6f\",\"destination_uuid\":null}],\"actions\":[{\"uuid\":\"4d4dc0f1-9056-4bf1-a58e-df26b861088e\",\"type\":\"send_msg\",\"text\":\"hehlo\",\"quick_replies\":[],\"attachments\":[]}]}],\"name\":\"hello\",\"localization\":{},\"language\":\"base\",\"expire_after_minutes\":10080,\"_ui\":{\"nodes\":{\"59c67035-59ab-47fa-a1fd-a50978aa78c5\":{\"type\":\"execute_actions\",\"position\":{\"top\":0,\"left\":0}}}}}}],\"contact_field\":[],\"collections\":[]}"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "importFlow": {
      "errors": null,
      "success": false
    }
  }
}
```

### Query Parameters

| Parameter | Type                     | Default  | Description |
| --------- | ------------------------ | -------- | ----------- |
| input     | <a href="#json">Json</a> | required |             |

### Return Parameters

| Type                                             | Description                      |
| ------------------------------------------------ | -------------------------------- |
| <a href="#flowresult">FlowResult</a> | The imported flow success status |

## Export a Flow

```graphql
mutation exportFlow($id: ID!) {
  publishFlow(id: $id) {
    export_data
    errors {
      key
      message
    }
  }
}

{
  "id": 10
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "exportFlow": {
      "export_data": "{\"flows\":[{\"vars\":[\"3fa22108-f464-41e5-81d9-d8a298854429\"],\"uuid\":\"3fa22108-f464-41e5-81d9-d8a298854429\",\"type\":\"message\",\"spec_version\":\"13.1.0\",\"nodes\":[{\"uuid\":\"3ea030e9-41c4-4c6c-8880-68bc2828d67b\",\"exits\":[{\"uuid\":\"a8311645-482e-4d35-b300-c92a9b18798b\",\"destination_uuid\":\"6f68083e-2340-449e-9fca-ac57c6835876\"}],\"actions\":[{\"uuid\":\"e319cd39-f764-4680-9199-4cb7da647166\",\"type\":\"send_msg\",\"text\":\"Thank you for reaching out. This is your help message along with some options-\\n      \\n*Type 1* for option 1\\n*Type 2* for option 2\\n*Type 3* for option 3\\n*Type 4* to optout and stop receiving our messages\",\"quick_replies\":[],\"attachments\":[]}]},{\"uuid\":\"6f68083e-2340-449e-9fca-ac57c6835876\",\"router\":{\"wait\":{\"type\":\"msg\"},\"type\":\"switch\",\"operand\":\"@input.text\",\"default_category_uuid\":\"65da0a4d-2bcc-42a2-99f5-4c9ed147f8a6\",\"categories\":[{\"uuid\":\"de13e275-a05f-41bf-afd8-73e9ed32f3bf\",\"name\":\"One\",\"exit_uuid\":\"744b1082-4d95-40d0-839a-89fc1bb99d30\"},{\"uuid\":\"d3f0bf85-dac1-4b7d-8084-5c1ad2575f12\",\"name\":\"Two\",\"exit_uuid\":\"77cd0e42-6a13-4122-a5fc-84b2e2daa1d4\"},{\"uuid\":\"243766e5-e353-4d65-b87a-4405dbc24b1d\",\"name\":\"Three\",\"exit_uuid\":\"0caba4c7-0955-41c9-b8dc-6c58112503a0\"},{\"uuid\":\"3ce58365-61f2-4a6c-9b03-1eeccf988952\",\"name\":\"Four\",\"exit_uuid\":\"1da8bf0a-827f-43d8-8222-a3c79bcace46\"},{\"uuid\":\"65da0a4d-2bcc-42a2-99f5-4c9ed147f8a6\",\"name\":\"Other\",\"exit_uuid\":\"d11aaf4b-106f-4646-a15d-d18f3a534e38\"}],\"cases\":[{\"uuid\":\"0345357f-dbfa-4946-9249-5828b58161a0\",\"type\":\"has_any_word\",\"category_uuid\":\"de13e275-a05f-41bf-afd8-73e9ed32f3bf\",\"arguments\":[\"1\"]},{\"uuid\":\"bc425dbf-d50c-48cf-81ba-622c06e153b0\",\"type\":\"has_any_word\",\"category_uuid\":\"d3f0bf85-dac1-4b7d-8084-5c1ad2575f12\",\"arguments\":[\"2\"]},{\"uuid\":\"be6bc73d-6108-405c-9f88-c317c05311ad\",\"type\":\"has_any_word\",\"category_uuid\":\"243766e5-e353-4d65-b87a-4405dbc24b1d\",\"arguments\":[\"3\"]},{\"uuid\":\"ebacc52f-a9b0-406d-837e-9e5ca1557d17\",\"type\":\"has_any_word\",\"category_uuid\":\"3ce58365-61f2-4a6c-9b03-1eeccf988952\",\"arguments\":[\"4\"]}]},\"exits\":[{\"uuid\":\"744b1082-4d95-40d0-839a-89fc1bb99d30\",\"destination_uuid\":\"f189f142-6d39-40fa-bf11-95578daeceea\"},{\"uuid\":\"77cd0e42-6a13-4122-a5fc-84b2e2daa1d4\",\"destination_uuid\":\"85e897d2-49e4-42b7-8574-8dc2aee97121\"},{\"uuid\":\"0caba4c7-0955-41c9-b8dc-6c58112503a0\",\"destination_uuid\":\"6d39df59-4572-4f4c-99b7-f667ea112e03\"},{\"uuid\":\"1da8bf0a-827f-43d8-8222-a3c79bcace46\",\"destination_uuid\":\"a5105a7c-0917-4900-a0ce-cb5d3be2ffc5\"},{\"uuid\":\"d11aaf4b-106f-4646-a15d-d18f3a534e38\",\"destination_uuid\":\"3ea030e9-41c4-4c6c-8880-68bc2828d67b\"}],\"actions\":[]},{\"uuid\":\"f189f142-6d39-40fa-bf11-95578daeceea\",\"exits\":[{\"uuid\":\"d002db23-a51f-4183-81d6-b1e93c5132fb\",\"destination_uuid\":\"ca4e201c-b500-418e-8fdf-97ac0d4a80a5\"}],\"actions\":[{\"uuid\":\"ed7d10f7-6298-4d84-a8d2-7b1f6e91da07\",\"type\":\"send_msg\",\"text\":\"Message for option 1\",\"quick_replies\":[],\"attachments\":[]}]},{\"uuid\":\"6d39df59-4572-4f4c-99b7-f667ea112e03\",\"exits\":[{\"uuid\":\"b913ee73-87d2-495b-8a2d-6e7c40f31fd5\",\"destination_uuid\":\"ca4e201c-b500-418e-8fdf-97ac0d4a80a5\"}],\"actions\":[{\"uuid\":\"10196f43-87f0-4205-aabd-1549aaa7e242\",\"type\":\"send_msg\",\"text\":\"Message for option 3\",\"quick_replies\":[],\"attachments\":[]}]},{\"uuid\":\"a5105a7c-0917-4900-a0ce-cb5d3be2ffc5\",\"exits\":[{\"uuid\":\"df45c811-b1fe-4d25-a925-88f8d7ad6fc9\",\"destination_uuid\":null}],\"actions\":[{\"uuid\":\"36051723-7d00-422e-8846-2336a9ecbc9d\",\"type\":\"send_msg\",\"text\":\"Message for option 4\",\"quick_replies\":[],\"attachments\":[],\"all_urns\":false},{\"value\":\"optout\",\"uuid\":\"690c3e48-d31a-4819-86a6-e6dc11aa8ff8\",\"type\":\"set_contact_field\",\"field\":{\"name\":\"Settings\",\"key\":\"settings\"}}]},{\"uuid\":\"85e897d2-49e4-42b7-8574-8dc2aee97121\",\"exits\":[{\"uuid\":\"37a545df-825b-4611-a7fe-b17dfb62c430\",\"destination_uuid\":\"ca4e201c-b500-418e-8fdf-97ac0d4a80a5\"}],\"actions\":[{\"uuid\":\"a970d5d9-2951-48dc-8c66-ee6833c4b21e\",\"type\":\"send_msg\",\"text\":\"Message for option 2. You can add them to a group based on their response.\",\"quick_replies\":[],\"attachments\":[\"image:https://www.buildquickbots.com/whatsapp/media/sample/jpg/sample01.jpg\"]}]},{\"uuid\":\"ca4e201c-b500-418e-8fdf-97ac0d4a80a5\",\"exits\":[{\"uuid\":" <> ...
    }
  }
} ,
    }
  }
}
```

### Query Parameters

| Parameter | Type                  | Default  | Description |
| --------- | --------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>! | required |             |

### Return Parameters

| Type                                        | Description                      |
| ------------------------------------------- | -------------------------------- |
| <a href="#exportFlow">ExportFlowResults</a> | An error object or response true |

## Get a flow

Gets a flow for the logged in user.

```graphql
query flowGet($id: ID!) {
  flowGet(id: $id) {
    id
    name
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "flowGet": {
      "id": "2",
      "name": "Activity"
    }
  }
}

OR if no flow is available

{
  "data": {
    "flowGet": null
  }
}
```

### Query Parameters

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |

### Return Parameters

| Type                     | Description   |
| ------------------------ | ------------- |
| <a href="#flow">Flow</a> | A flow object |

## Release a flow contact

Releases a flow for the logged in user if one exists. The system also releases the flow
when it has been idle for more than 10 minutes and there is a request for a flow

```graphql
query flowRelease {
  flowRelease {
    id
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "flowRelease": null
  }
}
```

### Query Parameters

| Parameter | Type | Default | Description |
| --------- | ---- | ------- | ----------- |

### Return Parameters

| Type | Description |
| ---- | ----------- |

## Flow Objects

### Flow

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
<td colspan="2" valign="top"><strong>flowType</strong></td>
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
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#uuid4">UUID4</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>versionNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ignoreKeywords</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isBackground</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
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
<tr>
<td colspan="2" valign="top"><strong>lastPublishedAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>lastChangedAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>
</tbody>
</table>

### FlowResult

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
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
</tbody>
</table>

## Flow Inputs

### FlowInput

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
<td colspan="2" valign="top"><strong>keywords</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>ignoreKeywords</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isBackground</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

### FlowFilter

Filtering options for flows

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
  <td>Match the flow name</td>
</tr>
<tr>
  <td colspan="2" valign="top"><strong>nameOrKeyword</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the flow name and keywords</td>
</tr>
<tr>
  <td colspan="2" valign="top"><strong>keyword</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the flow keyword</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>uuid</strong></td>
<td valign="top"><a href="#uuid4">UUID4</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>Match the isActive flag of flow</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isBackground</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>Match the isBackground flag of flow</td>
</tr>
<tr>
  <td colspan="2" valign="top"><strong>status</strong></td>
  <td valign="top"><a href="#string">String</a></td>
  <td>Match the status of flow revision draft/archived/published</td>
</tr>
</tbody>
</table>
