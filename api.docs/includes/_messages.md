# Messages

## Get All Messages

```graphql
query messages($filter: MessageFilter, $opts: Opts) {
  messages(filter: $filter, opts:$opts) {
    id
    body
    type
    sender {
        id,
        name
    }
  }
}

{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "body": "Hello"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "messages": [
      {
        "id": "3",
        "body": "Hello, how are you",
        "sender": {
            "id": "2",
            "name": "Default Sender"
        }

      },
      {
        "id": "15",
        "body": "Hello world",
        "sender": {
            "id": "13",
            "name": "Althea Hirthe"
        }

      }
    ]
  }
}
```
This returns all the messages for the organization filtered by the input <a href="#messagefilter">MessageFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#messagefilter">MessageFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Get a specific Message by ID

```graphql
query message($id: ID!) {
  message(id: $id) {
    message {
      id
      body
      receiver {
        id
        name
      }
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
    "message": {
      "message": {
        "id": "2",
        "body": "Can one desire too much of a good thing?.",
        "receiver": {
          "id": "10",
          "name": "Chrissy Cron"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a>

## Count all Messages

```graphql
query countMessages($filter: MessageFilter) {
  countMessages(filter: $filter)
}

{
  "filter": {
    "body": "hello"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countMessage": 2
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#messagefilter">MessageFilter</a> | nil | filter the list

## Create a Message

```graphql
mutation createMessage($input:MessageInput!) {
  createMessage(input: $input) {
    message {
      id
      body
      sender {
        id
        name
      }
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "body": "So wise so young, they say, do never live long.",
    "type": "TEXT"
    "flow": "TEXT"
    "senderId": 1,
    "receiverId": 3
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createMessage": {
      "errors": null,
      "message": {
        "id": "26",
        "body": "So wise so young, they say, do never live long.",
        "sender": {
          "id": "1",
          "name": "Adelle Cavin"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messageinput">MessageInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#messageresult">MessageResult</a> | The created message object

## Update a Message

```graphql
mutation updateMessage($id: ID!, $input:MessageInput!) {
  updateMessage(id: $id, input: $input) {
    message {
      id
      body
      sender {
        id
        name
      }
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
    "body": "It is the east, and Juliet is the sun."
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateMessage": {
      "errors": null,
      "message": {
        "id": "26",
        "body": "It is the east, and Juliet is the sun.",
        "sender": {
          "id": "3",
          "label": "Conrad Barton"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#messageInput">MessageInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#messageresult">MessageResult</a> | The updated message object


## Delete a Message

```graphql
mutation deleteMessage($id: ID!) {
  deleteMessage(id: $id) {
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
    "deleteMessage": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteMessage": {
      "errors": [
        {
          "key": "Elixir.Glific.Messages.Message 26",
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
<a href="#messageresult">MessageResult</a> | An error object or empty

## Delete a Messages of a contact

```graphql
mutation clearMessages($contactId: ID!) {
  clearMessages(contactId: $contactId) {
    success
    errors {
      key
      message
    }
  }
}

{
  "contactId": "26"
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "clearMessages": {
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
    "clearMessages": {
      "errors": [
        {
          "key": "Elixir.Glific.Contacts.Contact",
          "message": "Resource not found"
        }
      ],
      "success": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
contactId | <a href="#id">ID</a>! | required ||

### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#clearmessagesresult">ClearMessagesResult</a> | An error object or empty



## Create and send Message

```graphql
mutation createAndSendMessage($input: MessageInput!) {
  createAndSendMessage(input: $input) {
    message {
      id
      body
      receiver {
        id
        name
      }
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "body": "Test message",
    "flow": "OUTBOUND",
    "type": "TEXT",
    "senderId": 1,
    "receiverId": 2
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createAndSendMessage": {
      "errors": null,
      "message": {
        "body": "Test message",
        "id": "26",
        "receiver": {
          "id": "2",
          "name": "Default receiver"
        }
      }
    }
  }
}
```

```	```
## Create and send SessionTemplate

```graphql
mutation createAndSendMessage($input: MessageInput!) {
  createAndSendMessage(input: $input) {
    message {
      id
      body
      receiver {
        id
        name
      }
    }
    errors {
      key
      message
    }
  }
}
{
  "input": {
    "flow": "OUTBOUND",
    "type": "TEXT",
    "senderId": 1,
    "receiverId": 11,
    "isHsm": true,
    "params": ["Fifty", "Next Week"],
    "templateId": 32
    
  }
}
```

> The above query returns JSON structured like this:
```json
{
  "data": {
    "createAndSendMessage": {
      "__typename": "MessageResult",
      "errors": null,
      "message": {
        "__typename": "Message",
        "body": "Your Fifty points will expire on Next Week.",
        "id": "241",
        "isHsm": true,
        "params": null,
        "receiver": {
          "__typename": "Contact",
          "id": "11",
          "name": "Test"
        },
        "templateId": null
      }
    }
  }
}
```

## Create and send Scheduled Message

```graphql
mutation createAndSendMessage($input: MessageInput!) {
  createAndSendMessage(input: $input) {
    message {
      id
      body
      insertedAt
      sendAt
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "body": "This message should reach at 21:00 (India)",
    "flow": "OUTBOUND",
    "receiverId": 7,
    "sendAt": "2020-07-10T03:30:00Z",
    "senderId": 1,
    "type": "TEXT"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createAndSendMessage": {
      "errors": null,
      "message": {
        "body": "This message should reach at 21:00 (India)",
        "id": "33",
        "insertedAt": "2020-07-10T13:50:40Z",
        "sendAt": "2020-07-10T15:30:00Z"
      }
    }
  }
}
```

### Query Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messageinput">MessageInput</a> | required ||

### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messageresult">MessageResult</a> | An error object or empty



## Create and send Message to contacts of a group

```graphql
mutation createAndSendMessageToGroup($input: MessageInput!, $groupId: ID!) {
  createAndSendMessageToGroup(input: $input, groupId: $groupId) {
    success
    contactIds
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "body": "Test message",
    "flow": "OUTBOUND",
    "type": "TEXT",
    "senderId": 1
  },
  "groupId": 1
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createAndSendMessageToGroup": {
      "contactIds": [
        "8"
      ],
      "errors": null,
      "success": true
    }
  }
}
```

### Query Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messageinput">MessageInput</a> | required ||
groupId | [<a href="#id">ID</a>]! | required ||

### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
[<a href="#groupmessageresult">GroupMessageResult</a>] | List of contact ids


## Send hsm Message

```graphql
mutation sendHsmMessage($templateId: ID!, $receiverId: ID!, $parameters: [String]) {
  sendHsmMessage(templateId: $templateId, receiverId: $receiverId, parameters: $parameters) {
    message{
      id
      body
      isHsm
    }
    errors {
      key
      message
    }
  }
}

{
  "templateId": 34,
  "receiverId": 5,
  "parameters": [
    "100",
    "30 Oct"
  ]
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sendHsmMessage": {
      "errors": null,
      "message": {
        "body": "Your 100 points will expire on 30 Oct.",
        "id": "18",
        "isHsm": true
      }
    }
  }
}
```

> In case of error, above function returns an error object like the below

```json
{
  "data": {
    "sendHsmMessage": null
  },
  "errors": [
    {
      "locations": [
        {
          "column": 3,
          "line": 2
        }
      ],
      "message": "You need to provide correct number of parameters for hsm template",
      "path": [
        "sendHsmMessage"
      ]
    }
  ]
}
```

### Query Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
templateId | <a href="#id">ID</a>! | required ||
receiverId | <a href="#id">ID</a>! | required ||
parameters | [<a href="#string">String</a>]! | required ||

### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messageresult">MessageResult</a> | An error object or empty


## Subscription for Sent Message

```graphql
subscription {
  sentMessage() {
    id
    body
    flow
    type
    receiver {
        id
        phone
    }

    sender {
        id
        phone
    }
  }
}

```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "sentMessage": {
      "body": "Test",
      "flow": "OUTBOUND",
      "id" : "10397",
      "type": "TEXT",
      "receiver": {
          "id" : "484",
          "phone" : "91997612324"
      },
      "sender": {
          "id" : "1",
          "phone" : "917834811114"
      }
    }
  }
}
```
### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messageresult">MessageResult</a> | An error or object

## Subscription for Update Message Status

```graphql
subscription {
  update_message_status() {
    id
    body
    flow
    type
    status
    receiver {
        id
        phone
    }

    sender {
        id
        phone
    }
  }
}

```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "update_message_status": {
      "body": "Test",
      "flow": "OUTBOUND",
      "id" : "10397",
      "type": "TEXT",
      "status": "sent",
      "receiver": {
          "id" : "484",
          "phone" : "91997612324"
      },
      "sender": {
          "id" : "1",
          "phone" : "917834811114"
      }
    }
  }
}
```
### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messageresult">MessageResult</a> | An error or object


## Subscription for Received Message

```graphql
subscription {
  receivedMessage() {
    id
    body
    flow
    type
    receiver {
        id
        phone
    }

    sender {
        id
        phone
    }
  }
}

```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "sentMessage": {
      "body": "New Message",
      "flow": "OUTBOUND",
      "id" : "10397",
      "type": "TEXT",
      "receiver": {
          "id" : "1",
          "phone" : "917834811114"
      },
      "sender": {
          "id" : "3",
          "phone" : "91998782231"
      }
    }
  }
}
```
### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messageresult">MessageResult</a> | An error or an object



## Message Objects

### Message

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
<td colspan="2" valign="top"><strong>body</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#boolean">MessageTypesEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#boolean">MessageFlowEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>BspMessageId</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>BspStatus</strong></td>
<td valign="top"><a href="#string">MessageStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status</strong></td>
<td valign="top"><a href="#string">MessageStatusEnum</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>Sender</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>Receiver</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Media</strong></td>
<td valign="top"><a href="#messagemedia">MessageMedia</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>isHsm</strong></td>
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
<td colspan="2" valign="top"><strong>sendAt</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Tags</strong></td>
<td valign="top"><a href="#tags">Tags</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>user</strong></td>
<td valign="top"><a href="#user">User</a></td>
<td></td>
</tr>

</tbody>
</table>

### MessageResult ###

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
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#message">Message</a></td>
<td></td>
</tr>
</tbody>
</table>

### GroupMessageResult

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
<td colspan="2" valign="top"><strong>success</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contactIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
</tbody>
</table>

### ClearMessagesResult

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
<td colspan="2" valign="top"><strong>success</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

## Message Inputs ##

### MessageFilter ###

Filtering options for messages

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
<td>

Match the body

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Sender</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the sender name

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Sender</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the sender name

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Receiver</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the receiver name

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Either</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the phone with either the sender or receiver

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>Either</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the phone with either the sender or receiver

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>BspStatus</strong></td>
<td valign="top"><a href="#messagestatusenum">MessageStatusEnum</a></td>
<td>

Match the status

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>TagsIncluded</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Match the tags included

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>TagsExcluded</strong></td>
<td valign="top">[<a href="#gid">Gid</a>]</td>
<td>

Match the tags excluded

</td>
</tr>


</tbody>
</table>

### MessageInput ###

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
<td colspan="2" valign="top"><strong>type</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#message_flow_enum">MessageFlowEnum</a></td>
<td></td>
</tr>


<tr>
<td colspan="2" valign="top"><strong>sender_id</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>receiver_id</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>media_id</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>send_at</strong></td>
<td valign="top"><a href="#datetime">DateTime</a></td>
<td></td>
</tr>

</tbody>
</table>
