# SaaS

Start of the documentation and functionality to run Glific as your very own SaaS. In keeping
with our open source philosophy, everything we do will be open, to encourage more SaaS providers to
offer Glific locally

Billing with stripe is already included as part of the core platform, and hence will not be covered in this section.
As we make advances in that area, we will add more documentation

## Create an organization, organization contact and BSP credentials

One function to rule them all. Grab the minimum amount of information that we require from the user
to bootstrap their account. All the other functionality can be done via the main Glific interface

At this stage, this is open to the world. However the organization created is marked as not active AND
not approved, so they really cannot login. In the next version, we will add simple OTP based authentication
to ensure the Admin is opted in with the SaaS WhatsApp Business API Account.

```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
  "name": "Sample Organization",
  "shortcode": "sample",
  "phone": "WhatsApp Business API Registered number",
  "api_key": "Gupshup API Key",
  "app_name": "Gupshup App Name",
  "email": "Email Address of Admin",
}
```

> The above query returns JSON structured like this:

In the case of a validation failure

```json
{
  "is_valid": FALSE,
  "messages": ["Error Message 1", "Error Message 2", "Error Message 3"]
}
```

Or in the case of success

```json
{
  "is_valid": TRUE,
  "messages": [],
  "organization": "Organization Object",
  "contact": "Contact Object",
  "credential": "Credential Object"
}
```

## Update Organization Status IsActive or IsApproved

```graphql
mutation updateOrganizationStatus($id: ID!, $input: OrganizationStatusInput!) {
  updateOrganizationStatus(id: $id, input: $input) {
    organization {
      email
      isActive
      isApproved
      name
      shortcode
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
    "isActive": true,
    "isApproved": true,
    "updateOrganizationId": 1,
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateOrganizationStatus": {
      "errors": null,
      "organization": {
        "__typename": "Organization",
        "email": "ADMIN@gmail.com",
        "isActive": true,
        "isApproved": true,
        "name": "Glific",
        "shortcode": "glific"
      }
    }
  }
}
```

Enabled days Ids represets weekdays starting from 1 for Monday.

### Query Parameters

| Parameter | Type                                                           | Default  | Description |
| --------- | -------------------------------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                                          | required |             |
| input     | <a href="#organizationstatusinput">OrganizationStatusInput</a> | required |             |

### Return Parameters

| Type                                                 | Description                     |
| ---------------------------------------------------- | ------------------------------- |
| <a href="#organizationresult">OrganizationResult</a> | The updated organization object |

## Delete Organization with status as inactive

```graphql
mutation deleteInactiveOrganization($id: ID!, $input: DeleteOrganizationInput!) {
  deleteInactiveOrganization(id: $id, input: $input) {
    organization {
      email
      isActive
      isApproved
      name
      shortcode
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
    "isConfirmed": true,
    "deleteOrganizationId": 1,
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "deleteInactiveOrganization": {
      "errors": null,
      "organization": {
        "__typename": "Organization",
        "email": "ADMIN@gmail.com",
        "isActive": true,
        "isApproved": true,
        "name": "Glific",
        "shortcode": "glific"
      }
    }
  }
}
```

Enabled days Ids represets weekdays starting from 1 for Monday.

### Query Parameters

| Parameter | Type                                                           | Default  | Description |
| --------- | -------------------------------------------------------------- | -------- | ----------- |
| id        | <a href="#id">ID</a>!                                          | required |             |
| input     | <a href="#organizationstatusinput">OrganizationStatusInput</a> | required |             |

### Return Parameters

| Type                                                 | Description                     |
| ---------------------------------------------------- | ------------------------------- |
| <a href="#organizationresult">OrganizationResult</a> | The updated organization object |

### OrganizationStatusInput

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
<td colspan="2" valign="top"><strong>updateOrganizationId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td>

Unique

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isActive</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isApproved</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>

### DeleteInactiveOrganization

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
<td colspan="2" valign="top"><strong>deleteOrganizationId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td>

Unique

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>isConfirmed</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>
