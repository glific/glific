# Organizations

## Get All Organizations

```graphql
query organizations($filter: OrganizationFilter, $opts: Opts) {
  organizations(filter: $filter, opts: $opts) {
    id
    name
    defaultLanguage {
      id
      label
    }
  }
}

{
  "opts": {
    "limit": 10,
    "offset": 1,
    "order": "ASC"
  },
  "filter": {
    "defaultLanguage": "Hindi"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "organizations": [
      {
        "defaultLanguage": {
          "id": "1",
          "label": "Hindi"
        },
        "id": "1",
        "name": "Default Organization"
      },
      {
        "defaultLanguage": {
          "id": "1",
          "label": "Hindi"
        },
        "id": "2",
        "name": "Slam Out Loud"
      }
    ]
  }
}
```
This returns all the organizations filtered by the input <a href="#organizationfilter">OrganizationFilter</a>

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#organizationfilter">OrganizationFilter</a> | nil | filter the list
opts | <a href="#opts">Opts</a> | nil | limit / offset / sort order options

### Return Parameters
Type | Description
| ---- | -----------
[<a href="#organization">Organization</a>] | List of organization

## Get a specific Organization by ID

```graphql
query organization($id: ID!) {
  organization(id: $id) {
    organization {
      id
      name
      defaultLanguage {
        id
        label
      }
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
    "organization": {
      "organization": {
        "defaultLanguage": {
          "id": "1",
          "label": "Hindi"
        },
        "id": "1",
        "name": "Default Organization"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#organizationfilter">OrganizationFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#organizationresult">OrganizationResult</a> | Queried Organization

## Count all Organizations

```graphql
query countOrganizations($filter: OrganizationFilter) {
  countOrganizations(filter: $filter)
}

{
  "filter": {
    "language": "Hindi"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "countOrganizations": 2
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
filter | <a href="#organizationfilter">OrganizationFilter</a> | nil | filter the list

### Return Parameters
Type | Description
| ---- | -----------
<a href="#int">Int</a> | Count of filtered organization

## Create an Organization

```graphql
mutation createOrganization($input:OrganizationInput!) {
  createOrganization(input: $input) {
    organization {
      id
      name
      displayName
      contactName
			email
      provider {
        id
        name
      }
      providerKey
      providerNumber
      defaultLanguage {
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
    "name": "new_organization",
    "displayName": "new organization",
    "contactName": "organization's contact",
    "email": "test@test.com",
    "providerId": 1,
    "providerKey": "Key provided by provider",
    "providerNumber": "Number",
    "defaultLanguageId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createOrganization": {
      "errors": null,
      "organization": {
        "contactName": "organization's contact",
        "defaultLanguage": {
          "id": "1",
          "label": "Hindi"
        },
        "displayName": "new organization",
        "email": "test@test.com",
        "id": "3",
        "name": "new_organization",
        "provider": {
          "id": "1",
          "name": "Default Provider"
        },
        "providerKey": "Key provided by provider",
        "providerNumber": "Number"
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#organizationinput">OrganizationInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#organizationresult">OrganizationResult</a> | The created organization object

## Update an Organization

```graphql
mutation updateOrganization($id: ID!, $input: OrganizationInput!) {
  updateOrganization(id: $id, input: $input) {
    organization {
      id
      name
      displayName
      outOfOffice {
        enabled
        startTime
        endTime
        flowId
        enabledDays {
          id
          enabled
        }
      }
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
    "displayName": "updated organization display name",
    "outOfOffice": {
      "enabled": true,
      "enabledDays": [
        {
          "enabled": true,
          "id": 1
        },
        {
          "enabled": true,
          "id": 2
        },
        {
          "enabled": true,
          "id": 3
        },
        {
          "enabled": true,
          "id": 4
        },
        {
          "enabled": true,
          "id": 5
        },
        {
          "enabled": false,
          "id": 6
        },
        {
          "enabled": false,
          "id": 7
        }
      ],
      "endTime": "T19:00:00",
      "flowId": 1,
      "startTime": "T09:00:00"
    }
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateOrganization": {
      "errors": null,
      "organization": {
        "displayName": "updated organization display name",
        "id": "1",
        "name": "Glific",
        "outOfOffice": {
          "enabled": true,
          "enabledDays": [
            {
              "enabled": true,
              "id": 1
            },
            {
              "enabled": true,
              "id": 2
            },
            {
              "enabled": true,
              "id": 3
            },
            {
              "enabled": true,
              "id": 4
            },
            {
              "enabled": true,
              "id": 5
            },
            {
              "enabled": false,
              "id": 6
            },
            {
              "enabled": false,
              "id": 7
            }
          ],
          "endTime": "19:00:00",
          "flowId": "1",
          "startTime": "9:00:00"
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
input | <a href="#organizationinput">OrganizationInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#organizationresult">OrganizationResult</a> | The updated organization object


## Delete an Organization

```graphql
mutation deleteOrganization($id: ID!) {
  deleteOrganization(id: $id) {
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
    "deleteOrganization": {
      "errors": null
    }
  }
}
```

In case of errors, all the above functions return an error object like the below

```json
{
  "data": {
    "deleteOrganization": {
      "errors": [
        {
          "key": "Elixir.Glific.Partners.Organization 3",
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
Type | Description
--------- | ---- | ------- | -----------
<a href="#organizationresult">OrganizationResult</a> | An error object or empty

## Organization Objects

### Organization

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
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contactName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>defaultLanguage</strong></td>
<td valign="top"><a href="#language">Language</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>displayName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>email</strong></td>
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
<td colspan="2" valign="top"><strong>provider</strong></td>
<td valign="top"><a href="#provider">Provider</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerKey</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>outOfOffice</strong></td>
<td valign="top"><a href="#outofoffice">OutOfOffice</a></td>
<td></td>
</tr>
</tbody>
</table>

### OrganizationResult

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
<td colspan="2" valign="top"><strong>organization</strong></td>
<td valign="top"><a href="#organization">Organization</a></td>
<td></td>
</tr>
</tbody>
</table>

### OutOfOffice

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
<td colspan="2" valign="top"><strong>enabled</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>startTime</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>endTime</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>enabledDays</strong></td>
<td valign="top">[<a href="#enabledday">EnabledDay</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow_id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>

### EnabledDay

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
<td valign="top"><a href="#integer">Integer</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>enabled</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
</tbody>
</table>



## Organization Inputs ##


### OrganizationFilter

Filtering options for organizations

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
<td colspan="2" valign="top"><strong>contactName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the contact name

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>defaultLanguage</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the default language

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>displayName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the display name

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>email</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the email

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the name

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>provider</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the provider

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Match the whatsapp number of organization

</td>
</tr>
</tbody>
</table>

### OrganizationInput

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
<td colspan="2" valign="top"><strong>contactId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td>

Nullable

</td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>name</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td>

Unique

</td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>contactName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>defaultLanguageId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>displayName</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>email</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerKey</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>providerNumber</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>outOfOfficeInput</strong></td>
<td valign="top"><a href="#outofofficeinput">OutOfOfficeInput</a></td>
<td></td>
</tr>
</tbody>
</table>



### OutOfOfficeInput

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
<td colspan="2" valign="top"><strong>enabled</strong></td>
<td valign="top"><a href="#boolean">Boolean</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>startTime</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>endTime</strong></td>
<td valign="top"><a href="#time">Time</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>enabledDays</strong></td>
<td valign="top">[<a href="#enableddayinput">EnabledDayInput</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>flow_id</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>

### EnabledDayInput

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
<td valign="top"><a href="#integer">Integer</a>!</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>enabled</strong></td>
<td valign="top"><a href="#boolean">Boolean</a>!</td>
<td></td>
</tr>
</tbody>
</table>
