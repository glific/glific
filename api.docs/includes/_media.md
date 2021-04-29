# Media Management

Start of the documentation and functionality to incorporate media management into Glific. Note
that this will start off as a simple trivial layer over google cloud storage.

Base functionality will be to upload the files to a GCS public bucket, get the url from GCS, to return to
client (frontend). Client can then use this url, in a media message to send to WhatsApp user

## Upload a file

```graphql
mutation uploadMedia($media: Upload!, $type: String!) {
  uploadMedia(media: $media., type: $type)
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
mutation uploadBlob($media: String!, $type: String!) {
  uploadBlob(media: $media., type: $type)
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
