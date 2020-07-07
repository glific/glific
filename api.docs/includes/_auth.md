# Authentication

Authorization in Glific is still at a prototype stage and is not currently enforced by the system.
We do **not** use GraphQL for authorization, but use REST to generate and renew tokens. The
authentication tokens should be included in all GraphQL requests. This section will be expanded to also
include roles and permissions. User management will be done via GraphQL

The main API endpoints are listed below

## Create a new user

```shell
curl -X POST -d \
  "user[name]='Test User'&user[phone]=911234554321&user[password]=secret1234 \
  &user[password_confirmation]=secret1234&user[otp]=321721" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration
```

```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "name": "Test User",
        "phone": "911234554321",
        "password": "secret1234",
        "password_confirmation": "secret1234",
        "otp": "321721"
    }
}
```

> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```

Glific expects for the auth token to be included in all API requests to the server in a header
that looks like the following:

`Authorization: AUTH_TOKEN`


## Send an OTP request to verify a phone number

The OTP will be sent via WhatsApp and the NGO's Glific Instance. The API will only send
a message to contacts that have opted into the system. This also prevents the API
from being abused.

```shell
curl -X POST -d \
  "user[phone]=911234554321" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration/send_otp
```
```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "phone": "911234554321"
    }
}
```
> The above query returns JSON structured like this:

```json
{"data": {"phone": phone,
          "message": "OTP #{otp} sent successfully to #{phone}"}}
```

## Create a new session for an existing user

```shell
curl -X POST -d \
  "user[phone]=911234554321&user[password]=secret1234" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/session
```
```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "phone": "911234554321",
        "password": "secret1234"
    }
}
```
> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```

## Renew an existing session

```shell
curl -X POST -H "Authorization: RENEW_TOKEN" \
  http://localhost:4000/api/v1/session/renew
```

> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```
## Delete an existing session

```shell
curl -X DELETE -H "Authorization: AUTH_TOKEN" \
  http://localhost:4000/api/v1/session
```

> The above query returns JSON structured like this:

```json
{"data":{}}
```
