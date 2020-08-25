# Messages Tags

## Create a Message Tag

```graphql
mutation createMessageTag($input:MessageTagInput!) {
  createMessageTag(input: $input) {
    messageTag {
      id
      value
      message {
        id
        body
      }

      tag {
        id
        label
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
    "messageId": 2,
    "tagId": 3
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "messageTag": {
      "errors": null,
      "messageTag": {
        "id": 10,
        "value": "1",
        "message": {
          "id" : 2,
          "body": "one"
        },
        "tag": {
          "id" : 3,
          "label": "Numeric"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messagetaginput">MessageTagInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#messagetagresult">MessageTagResult</a> | The created message tag object

## Update a Message with tags to be added and tags to be deleted

```graphql
mutation updateMessageTags($input: MessageTagsInput!) {
  updateMessageTags(input: $input) {
    messageTags {
       id,
      message {
        body
      }

      tag {
        label
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
    "messageId": 2,
    "addTagIds": [3, 4, 5, 6]
    "deleteTagIds": [7, 8]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateMessageTags": {
      "errors": null,
      "messageTags": {
         {
          "id": "11476",
          "message": {
            "body": "Thank you"
          },
          "tag": {
            "label": "Good Bye"
          }
        },

        {
          "id": "11475",
          "message": {
            "body": "message body for order test"
          },
          "tag": {
            "label": "Compliment"
          }
        }

      },
      numberDeleted: 2,
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#messagetagsinput">MessageTagsInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#message_tags">messageTags</a> | The list of tag messages added
integer | The number of messages deleted


## Delete a Message Tag

```graphql
mutation deleteMessageTag($id: ID!) {
  deleteMessageTag(id: $id) {
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
    "deleteMessageTag": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteMessageTag": {
      "errors": [
        {
          "key": "Elixir.Glific.Messages.MessageTag 26",
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
<a href="#messagetagresult">MessageTagResult</a> | An error object or empty

## Subscription for Create Message Tag

```graphql
subscription {
  createdMessageTag {
    message{
      id
    }
    tag{
      id
    }
  }
}

```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "createdMessageTag": {
      "message": {
        "id": "194"
      },
      "tag": {
        "id": "194"
      }
    }
  }
}
```


### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#message">Message</a> | An error or object




## Subscription for Delete Message Tag

```graphql
subscription {
  updateMessageTags() {
    messageTags{
      message{
        body
      }
    }
    numberDeleted
  }
}

```
> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateMessageTags": {
      "messageTags": [],
      "numberDeleted": 1
    }
  }
}
```
### Return Parameters
Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
<a href="#messagetag">MessageTags</a> | An error or object



## Message Tag Objects

### MessageTag

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
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#message">Message</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>tag</strong></td>
<td valign="top"><a href="#tag">Tag</a></td>
<td></td>
</tr>
</tbody>
</table>

### MessageTags

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
<td colspan="2" valign="top"><strong>messageTags</strong></td>
<td valign="top">[<a href="#messagetag">MessageTag</a>]</td>
<td></td>
</tr>

</tbody>
</table>

### MessageTagResult ###

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
<td colspan="2" valign="top"><strong>MessageTag</strong></td>
<td valign="top"><a href="#messagetag">MessageTag</a></td>
<td></td>
</tr>
</tbody>
</table>

## Message Media Inputs ##

### MessageTagInput ###

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
<td colspan="2" valign="top"><strong>MessageId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>TagId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

</tbody>
</table>


### MessageTagsInput ###

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
<td colspan="2" valign="top"><strong>MessageId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>TagsId</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>

</tbody>
</table>
