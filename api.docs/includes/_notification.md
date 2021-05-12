# Notifications

## Get All Notifications

```graphql
query notifications($filter: NotificationFilter, $opts: Opts) {
  notifications(filter: $filter, opts: $opts) {
    id
    category
    entity
    insertedAt
    message
    severity
    updatedAt
  }
}


{
  "opts": {
    "order": "ASC",
    "limit": 10,
    "offset": 0
  },
  "filter": {
    "category": "Message",
    "message":  "Cannot send session message to contact, invalid bsp status."
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "notifications": [
      {
        "__typename": "Notification",
        "category": "Message",
        "entity": "{\"status\":\"valid\",\"phone\":\"3305447045\",\"name\":\"Adelle Cavin\",\"last_message_at\":\"2021-03-24T09:50:22Z\",\"is_hsm\":null,\"id\":9,\"group_id\":null,\"flow_id\":null,\"bsp_status\":\"hsm\"}",
        "id": "1",
        "insertedAt": "2021-03-24T11:40:26Z",
        "message": "Cannot send session message to contact, invalid bsp status.",
        "severity": "\"Error\"",
        "updatedAt": "2021-03-24T11:40:26Z"
      }
    ]
  }
}
```

This returns all the notifications for the organization filtered by the input <a href="#Notificationfilter">NotificationFilter</a>

### Query Parameters

| Parameter | Type                                                 | Default | Description                         |
| --------- | ---------------------------------------------------- | ------- | ----------------------------------- |
| filter    | <a href="#Notificationfilter">NotificationFilter</a> | nil     | filter the list                     |
| opts      | <a href="#opts">Opts</a>                             | nil     | limit / offset / sort order options |

## Count all Notifications

```graphql
query countNotifications($filter: NotificationFilter) {
  countNotifications(filter: $filter)
}

{
  "filter": {
    "category": "Message"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countNotifications": 2
  }
}
```

### Query Parameters

| Parameter | Type                                                 | Default | Description     |
| --------- | ---------------------------------------------------- | ------- | --------------- |
| filter    | <a href="#Notificationfilter">NotificationFilter</a> | nil     | filter the list |


## Mark all the notification as read

```graphql
mutation markNotificationAsRead {
  markNotificationAsRead
}

```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "markNotificationAsRead": true,
    "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#contactinput">ContactInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactresult">ContactResult</a> | The created contact object


## Notification Objects

### NotificationFilter

Filtering options for notifications

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
<td colspan="2" valign="top"><strong>category</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the category

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the message

</td>
</tr>
</td>
</tr>
</tbody>
</table>

### Notification

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
<td colspan="2" valign="top"><strong>category</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>is_read</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>entity</strong></td>
<td valign="top"><a href="#json">Json</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>severity</strong></td>
<td valign="top"><a href="#string">String</a></td>
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

### NotificationResult

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
<td colspan="2" valign="top"><strong>notification</strong></td>
<td valign="top"><a href="#notification">Notification</a></td>
<td></td>
</tr>
</tbody>
</table>

## Notification Inputs

### NotificationFilter

Filtering options for notifications

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
<td colspan="2" valign="top"><strong>message</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the message</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>category</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the category</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>is_read</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td>Filter read and unread notifications</td>
</tr>
</tbody>
</table>
