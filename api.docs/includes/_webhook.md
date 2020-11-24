# Webhooks

Webhooks in Glific are called from floweditor as part of a flow. You need to choose, "Call a webhook"
as the action of a node. We recommend that you implement the POST method for your webhook. This is because
we currently send a standard body as part of the webhook which includes potentially sensitive contact related
information.

Also give a meaninful name to the 'result'. So for a webhook that computes the survey score based on the
user responses in the flow, the name can be 'survey'.

## Prerequisites

You need to host and maintain a public URL that is the destination of your webhook.

## Webhook parameters

Glific sends a standard json object with the following fields as the POST body. In a future version
of Glific, the value that will be sent will be configurable

```json
{
  "contact": {
    "id": "ID of contact in Glific Database",
    "name": "Name of Contact",
    "phone": "Phone of Contact",
    "fields": {
      "field 1 key": "field 1 value",
      "field 2 key": "field 2 value",
      ...
      "field n key": "field n value"
    }
  },
  "results": {
    "result 1 key": "result 1 value",
    "result 2 key": "result 2 value",
    ...
    "result n key": "result n value"
  }
}
```

## Webhook Authentication

By default, Glific adds an extra signature header to each webhook to indicate that this was sent from Glific. This
signature key is generated using the signature phrase you set up for your organization and is also encrypted with
the current time, which is part of the signature payload. More details on how we sign the payload and how to verify
its accuracy can be found in [How we verifu webhooks](https://dashbit.co/blog/how-we-verify-webhooks)

## Webhook Return Values

On successful completion of the webhook, return a status code of 200 along with a JSON body. The JSON body, should only
be composed of {key, value} pairs. Each of these key value pairs is then stored in the flow "results" map, with the key
being appended to the variable indicated in the "Call a Webhook" node.

Thus is your 'survey' webhook, returns two values: 'score', 'message', Glific will add:

```json
{
  "results": {
    ... (results in flow currently)
    "survey_score": "Score you set in webhook",
    "survey_message": "Message you want to send next to the user"
  }
}
```

The format of the return value is here

```json
{
    "return 1 key": "return 1 value",
    "return 2 key": "return 2 value",
    ...
    "return n key": "return n value"
}
```

An example implementation of a webhook can be seen in our [github repository](https://github.com/glific/glific/blob/master/lib/glific/clients/stir.ex)
