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

Glific sends a standard json object with contact and results fields as default fields in the POST body. In addition to that Glific supports sending additional data in form of JSON fields.

```json
{
  "contact": {
    "name": "Name of Contact",
    "phone": "Phone of Contact",
    "fields": {
      "field 1 key": {
        "type": "type of field",
        "label": "label of field",
        "value": "value of field",
        "inserted_at": "inserted time of field"
      },
      ...
      "field n key": {
          "type": "type of field",
          "label": "label of field",
          "value": "value of field",
          "inserted_at": "inserted time of field"
      }
    }
  },
  "results": {
    "result 1 key": {
      "input": "input of result",
      "category": "category of result"
    },
    ...
    "result n key": {
      "input": "input of result",
      "category": "category of result"
    },
  },
  "custom_key": "custom_value"
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

Thus if your 'survey' webhook, returns three values: 'score', 'message', 'content',  Glific will add:

```json
{
  "results": {
    ... (results in flow currently)
    "survey.score": "Score you set in webhook",
    "survey.message": "Message you want to send next to the user",
    "survey.content": "Content you want to send next to the user"
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
