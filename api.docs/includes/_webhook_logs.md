# WebhookLogs

## Get All WebhookLogs

```graphql
query webhookLogs($filter: WebhookLogFilter, $opts: Opts) {
  webhookLogs(filter: $filter, opts: $opts) {
    id
    url
    method
    requestHeaders
    requestJson
    statusCode
    responseJson
    error
    insertedAt
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
    "statusCode": 200,
    "url":  "http://api.glific.test:4000/webhook/stir/survey"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "webhookLogs": [
      {
        "error": null,
        "id": "1",
        "insertedAt": "2020-12-29T06:30:14Z",
        "method": "POST",
        "requestHeaders": "{\"X-Glific-Signature\":\"t=1609223414,v1=6509abe916884f9f2b4e98ec12ab648c811f31a4c1f9b92335c8e990363304ef\",\"Content-Type\":\"application/json\",\"Accept\":\"application/json\"}",
        "requestJson": "{\"results\":{\"A2\":{\"input\":\"n\",\"category\":\"N\"},\"A1\":{\"input\":\"y\",\"category\":\"Y\"}},\"custom_key\":\"custom_value\",\"contact\":{\"phone\":\"9876543210\",\"name\":\"Simulator\"}}",
        "responseJson": "{\"status\":\"5\",\"score\":\"1\",\"content\":\"Your score: 1 is not divisible by 2, 3, 5 or 7\",\"art_result\":2,\"art_content\":\"    *2*. Space for practicing a classroom strategy \\n  \"}",
        "statusCode": 200,
        "updatedAt": "2020-12-29T06:30:14Z",
        "url": "http://api.glific.test:4000/webhook/stir/survey"
      }
    ]
  }
}
```
This returns all the webhook_logs for the organization filtered by the input <a href="#webhooklogfilter">WebhookLogFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#webhooklogfilter">WebhookLogFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

## Count all WebhookLogs

```graphql
query countWebhookLogs($filter: WebhookLogFilter) {
  countWebhookLogs(filter: $filter)
}

{
  "filter": {
    "statusCode": 200
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countWebhookLogs": 2
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#webhooklogfilter">WebhookLogFilter</a> | nil | filter the list

## WebhookLog Objects

### WebhookLog

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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>method</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>error</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow</strong></td>
<td valign="top"><a href="#flow">Flow</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
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

### WebhookLogResult ###

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
<td colspan="2" valign="top"><strong>webhook_log</strong></td>
<td valign="top"><a href="#webhooklog">WebhookLog</a></td>
<td></td>
</tr>
</tbody>
</table>

## WebhookLog Inputs ##


### WebhookLogFilter ###

Filtering options for webhook_logs

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
<td colspan="2" valign="top"><strong>url</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the url</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>status_code</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>Match the status code</td>
</tr>
</tbody>
</table>
