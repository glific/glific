# Templates Tags

## Create a Template Tag

```graphql
mutation createTemplateTag($input:TemplateTagInput!) {
  createTemplateTag(input: $input) {
    templateTag {
      id
      value
      template {
        id
        label
      }

      tag {
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
    "templateId": 2,
    "tagId": 3
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "createTemplateTag": {
      "errors": null,
      "templateTag": {
        "id": "1",
        "tag": {
          "id": "3",
          "label": "Greetings"
        },
        "template": {
          "id": "2",
          "label": "Message"
        },
        "value": null
      }
    }
  }
}
```

### Query Parameters

Parameter | Type | Default | Description
--------- | ---- | ------- | -----------
input | <a href="#templatetaginput">TemplateTagInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#templatetagresult">TemplateTagResult</a> | The created template tag object

## Update a Template with tags to be added and tags to be deleted

```graphql
mutation updateTemplateTags($input: TemplateTagsInput!) {
  updateTemplateTags(input: $input) {
    templateTags {
      id
      template {
        label
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
    "templateId": 2,
    "addTagIds": [3, 6],
    "deleteTagIds": [7, 8]
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "updateTemplateTags": {
      "numberDeleted": 2,
      "templateTags": [
        {
          "id": "29",
          "tag": {
            "label": "Thank You"
          },
          "template": {
            "label": "OTP Message"
          }
        },
        {
          "id": "28",
          "tag": {
            "label": "Good Bye"
          },
          "template": {
            "label": "OTP Message"
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
input | <a href="#templatetagsinput">TemplateTagsInput</a> | required ||

### Return Parameters
Type | Description
| ---- | -----------
<a href="#templatetags">templateTags</a> | The list of template tags added
integer | The number of template tags deleted



## Subscription for Create Template Tag

```graphql
subscription {
  createdTemplateTag {
    template{
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
    "createdTemplateTag": {
      "template": {
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
<a href="#message">Template</a> | An error or object





## Template Tag Objects

### TemplateTag

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
<td colspan="2" valign="top"><strong>value</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>

<tr>
<td colspan="2" valign="top"><strong>template</strong></td>
<td valign="top"><a href="#sessiontemplate">SessionTemplate</a></td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>tag</strong></td>
<td valign="top"><a href="#tag">Tag</a></td>
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
<td colspan="2" valign="top"><strong>templateTags</strong></td>
<td valign="top">[<a href="#templatetag">TemplateTag</a>]</td>
<td></td>
</tr>

</tbody>
</table>

### TemplateTagResult ###

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
<td colspan="2" valign="top"><strong>TemplateTag</strong></td>
<td valign="top"><a href="#templatetag">TemplateTag</a></td>
<td></td>
</tr>
</tbody>
</table>
