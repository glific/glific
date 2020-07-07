# Registration

## Send OTP

```graphql
mutation ($input: RegistrationInput!) {
  sendOtp (input: $input)
}

{
  "input": {
    "phone": "7891236543"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "sendOtp": "OTP 871307 sent successfully to 7891236543"
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#registrationinput">RegistrationInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#string">String</a> | Confirmation string with OTP and phone number

## Registration Inputs

### RegistrationInput

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
<td colspan="2" valign="top"><strong>password</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>phone</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>
