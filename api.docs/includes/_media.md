# Media Management

Start of the documentation and functionality to incorporate media management into Glific. Note
that this will start off as a simple trivial layer over google cloud storage.

Base functionality will be to upload the files to a GCS public bucket, get the url from GCS, to return to
client (frontend). Client can then use this url, in a media message to send to WhatsApp user

## Upload a file

```graphql
mutation uploadMedia($media: Upload!, $extension: String!) {
  uploadMedia(media: $media, extension: $extension)
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "uploadMedia":"https://storage.googleapis.com/BUCKET/uploads/outbound/2021-17/NGO Main Account/70253d8b-e419-425f-ad24-7878eb8eb687.png"
   }
}
```


## Upload a buffer

The media blob has to be encoded in base64

```graphql
mutation uploadBlob($media: String!, $extension: String!) {
  uploadBlob(media: $media, extension: $extension)
}

{
  "input": {
    "media": "W29iamVjdCBCbG9iXQ==",
    "extension": "wav"
  }
}
```

> The above query returns JSON structured like this:

```json
{
  "data": {
    "uploadBlob":"https://storage.googleapis.com/BUCKET/uploads/outbound/2021-17/NGO Main Account/70253d8b-e419-425f-ad24-7878eb8eb687.png"
   }
}
```
### BlobInput

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
<td colspan="2" valign="top"><strong>media</strong></td>
<td valign="top">[<a href="#string">String</a>]</td>
<td></td>
</tr>
<tr>
<td colspan="2" valign="top"><strong>extension</strong></td>
<td valign="top"><a href="#string">String</a></td>
<td></td>
</tr>
</tbody>
</table>