# Contact Tag

Join table between contacts and tags

## Create Contact Tag
```graphql
mutation createContactTag($input: ContactTagInput!) {
  createContactTag(input: $input) {
    contactTag {
      id
      contact {
        id
        name
      }
      tag {
        id
        label
        parent {
          id
          label
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
  "input": {
    "contactId": 2,
    "tagId": 20
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createContactTag": {
      "contactTag": {
        "contact": {
          "id": "2",
          "name": "Default receiver"
        },
        "id": "8",
        "tag": {
          "id": "20",
          "label": "Participant",
          "parent": {
            "id": "2",
            "label": "Contacts"
          }
        }
      },
      "errors": null
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#contacttaginput">ContactTagInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contacttagresult">ContactTagResult</a> | The created contact tag object

## Update a Contact with tags to be added and tags to be deleted

```graphql
mutation updateContactTags($input: ContactTagsInput!) {
  updateContactTags(input: $input) {
    contactTags {
      id
      contact {
        name
      }
      tag {
        label
      }
    }
    numberDeleted
  }
}
{
  "input": {
    "contactId": 2,
    "addTagIds": [3, 6],
    "deleteTagIds": [7, 8]
  }
}
```

> The above query returns JSON structured like this:
```json
{
  "data": {
    "updateContactTags": {
      "numberDeleted": 2,
      "contactTags": [
        {
          "id": "29",
          "tag": {
            "label": "Thank You"
          },
          "contact": {
            "name": "Default receiver"
          }
        },
        {
          "id": "28",
          "tag": {
            "label": "Good Bye"
          },
          "contact": {
            "name": "Default receiver"
          }
        }
      ]
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#contacttagsinput">ContactTagsInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#contacttags">contactTags</a> | The list of contact tags added
integer | The number of contact tags deleted

## Subscription for Create Contact Tag

```graphql
subscription {
  createdContactTag {
    contact{
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
    "createdContactTag": {
      "contact": {
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
<a href="#contacttag">ContactTag</a> | An error or object


## Subscription for Delete Contact Tag

```graphql
subscription {
  deletedContactTag() {
    contact{
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
    "deletedContactTag": {
      "contact": {
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
<a href="#contacttag">ContactTag</a> | An error or object


## ContactTag Objects

### ContactTag

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
<td colspan="2" valign="top"><strong>contact</strong></td>
<td valign="top"><a href="#contact">Contact</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>tag</strong></td>
<td valign="top"><a href="#tag">Tag</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>

### TemplateTags

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
<td colspan="2" valign="top"><strong>contactTags</strong></td>
<td valign="top">[<a href="#contacttag">ContactTag</a>]</td>
<td></td>
</tr>

</tbody>
</table>

### ContactTagResult

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
<td colspan="2" valign="top"><strong>contactTag</strong></td>
<td valign="top"><a href="#contacttag">ContactTag</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>errors</strong></td>
<td valign="top">[<a href="#inputerror">InputError</a>]</td>
<td></td>
</tr>
</tbody>
</table>

## ContactTag Inputs

### ContactTagInput

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
<td colspan="2" valign="top"><strong>tagId</strong></td>
<td valign="top"><a href="#id">ID</a></td>
<td></td>
</tr>
</tbody>
</table>

### ContactTagsInput ###

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
<td colspan="2" valign="top"><strong>ContactId</strong></td>
<td valign="top"><a href="#id">Id</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>AddTagIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]!</td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>DeleteTagIds</strong></td>
<td valign="top">[<a href="#id">Id</a>]!</td>
<td></td>
</tr>

</tbody>
</table>