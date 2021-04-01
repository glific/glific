# Billings

## Get a specific Billing by ID

```graphql
query billing($id: ID!) {
  billing(id: $id) {
    billing {
      id
      name
      email
      stripe_customer_id
      currency
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
    "billing": {
      "billing": {
        "id": "2",
        "name": "john",
        "email": "john@gmail.com",
        "stripe_customer_id": "cus_JDpMYdepEhvKnd",
        "currency": "USD",
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
ID | <a href="#id">ID</a> | nil ||

## Create a Billing

```graphql
mutation createBilling($input:BillingInput!) {
  createBilling(input: $input) {
    billing {
      id
      name
      email
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "name": "john",
    "email": "john@gmail.com"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createBilling": {
      "errors": null,
      "billing": {
        "id": "2",
        "name": "john",
        "email": "john@gmail.com"
        }
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#billinginput">BillingInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#billingresult">BillingResult</a> | The created billing object

## Update a Billing

```graphql
mutation updateBilling($id: ID!, $input:BillingInput!) {
  updateBilling(id: $id, input: $input) {
    billing {
      id
      name
      email
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
    "name": "frank",
    "email": "frank@gmail.com"
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateBilling": {
      "errors": null,
      "billing": {
        "name": "frank",
        "email": "frank@gmail.com"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a>! | required ||
input | <a href="#billinginput">BillingInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#billingresult">BillingResult</a> | The updated billing object

## Update Payment Method

```graphql
mutation updatePaymentMethod($id: ID!, $input:PaymentMethodInput!) {
  updatePaymentMethod(input: $input) {
    billing {
      currency
      email
      id
      name
      stripePaymentMethodId
      stripeCustomerId
    }
    errors {
      key
      message
    }
  }
}

{
  "input": {
    "stripePaymentMethodId": "pm_1IbONxSAmm68Jt0wLWwLIPa",
  }
}```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updatePaymentMethod": {
      "errors": null,
      "billing": {
        "currency": "USD",
        "email": "akhilesh@gmail.com",
        "id": "1",
        "name": "akhilesh",
        "stripeCustomerId": "cus_JDpMYdepEhvKnd",
        "stripePaymentMethodId": "pm_1IbONxSAmm68Jt0wLWwLIPa"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#paymentmethodinput">PaymentMethodInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#billingresult">BillingResult</a> | The updated billing object


## Delete a Billing

```graphql
mutation deleteBilling($id: ID!) {
  deleteBilling(id: $id) {
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
    "deleteBilling": {
      "errors": null,
      "billing": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteBilling": {
      "errors": [
        {
          "key": "Elixir.Glific.Partners.Billing",
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
<a href="#billingresult">BillingResult</a> | An error object or empty

## Billing Objects

### Billing

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
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>email</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>currency</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>stripe_customer_id</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>stripe_payment_method_id</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>stripe_current_period_start</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>stripe_current_period_end</strong></td>
<td valign="top"><a href="#time">Time</a></td>
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

### BillingResult ###

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
<td colspan="2" valign="top"><strong>billing</strong></td>
<td valign="top"><a href="#billing">Billing</a></td>
<td></td>
</tr>
</tbody>
</table>

### BillingInput ###

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

<tr>
<td colspan="2" valign="top"><strong>email</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>currency</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

</tbody>
</table>

### PaymentMethodInput

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
<td colspan="2" valign="top"><strong>stripe_payment_method_id</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>