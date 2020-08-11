# Contact Group

Join table between contacts and groups

## Create Contact Group
```graphql
mutation createContactGroup($input: ContactGroupInput!) {
  createContactGroup(input: $input) {
    contactGroup {
      id
      contact {
        id
        name
      }
      group {
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
    "contactId": 2,
    "groupId": 1
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createContactGroup": {
      "contactGroup": {
        "contact": {
          "id": "2",
          "name": "Default receiver"
        },
        "group": {
          "id": "1",
          "label": "My First Group"
        },
        "id": "1"
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#contactgroupinput">ContactGroupInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactgroupresult">ContactGroupResult</a> | The created contact group object

## Update a Group with contacts to be added and contacts to be deleted

```graphql
mutation updateGroupContacts($input: GroupContactsInput!) {
  updateGroupContacts(input: $input) {
    groupContacts {
      id
      group {
        label
      }
      contact {
        name
      }
    }
    numberDeleted
  }
}

{
  "input": {
    "groupId": 2,
    "addContactIds": [1, 2],
    "deleteContactIds": [3, 8]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateGroupContacts": {
      "groupContacts": [
        {
          "contact": {
            "name": "Default Receiver"
          },
          "group": {
            "label": "Art"
          },
          "id": "2"
        },
        {
          "contact": {
            "name": "Glific Admin"
          },
          "group": {
            "label": "Art"
          },
          "id": "1"
        }
      ],
      "numberDeleted": 1
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#groupcontactsinput">GroupContactsInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#group_contacts">groupContacts</a> | The list of contact groups added
integer | The number of contact groups deleted

## Delete a ContactGroup

```graphql
mutation deleteContactGroup($id: ID!) {
  deleteContactGroup(id: $id) {
    errors {
      key
      message
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
    "deleteContactGroup": {
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
id | <a href="#id">ID</a> | required |

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contactgroupresult">ContactGroupResult</a> | An error object or empty


## ContactGroup Objects

### ContactGroup

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
<td colspan="2" valign="top"><strong>group</strong></td>
<td valign="top"><a href="#group">Group</a></td>
<td></td>
</tr>
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
</tbody>
</table>

### ContactGroupResult

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
<td colspan="2" valign="top"><strong>contactGroup</strong></td>
<td valign="top"><a href="#contactgroup">ContactGroup</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## ContactGroup Inputs

### ContactGroupInput

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
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>groupId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>

### GroupContactsInput ###

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
<td colspan="2" valign="top"><strong>GroupId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>AddContactIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>DeleteContactIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]</td>
<td></td>
</tr>
</tbody>
</table>
