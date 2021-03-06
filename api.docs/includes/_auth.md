# Authentication

We do **not** use GraphQL for authorization, but use REST to generate and renew tokens. The
authentication tokens should be included in all GraphQL requests. This section will be expanded to also
include roles and permissions. User management will be done via GraphQL

The main API endpoints are listed below

## Send an OTP request to verify a phone number

The OTP will be sent via WhatsApp and the NGO's Glific Instance. The API will only send
a message to contacts that have opted into the system. This also prevents the API
from being abused.

```shell
curl -X POST -d \
  "user[phone]=911234554321" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration/send-otp
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
          "message": "OTP sent successfully to #{phone}"}}
```
Or

```json
{"error": { "message": "Cannot send the otp to #{phone}"}}
```

## Send an OTP request to verify a phone number of existing user

The OTP will be sent via WhatsApp and the NGO's Glific Instance. The API will only send
a message to existing user

```shell
curl -X POST -d \
  "user[phone]=911234554321&user[registration]=false" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration/send-otp
```
```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "phone": "911234554321",
        "registration": "false"
    }
}
```
> The above query returns JSON structured like this:

```json
{"data": {"phone": phone,
          "message": "OTP sent successfully to #{phone}"}}
```
> Or

```json
{"error": { "message": "Cannot send the otp to #{phone}"}}
```

## Create a new user

The typical user registration flow will be something like:

  * User follows the instructions at [gupshup.io](https://www.gupshup.io/whatsappassistant/#/whatsapp-dashboard)
  to optin to the NGO's WhatsApp Business API Account.
  * User enters: `Name`, `Phone Number` and `Password`
  * After initial validation, the caller will call the `send_otp` request
  * On successful confirmation of the delivery of `send_otp`, the front-end will display an OTP entry screen to the user.
  * On successful entry of the OTP, the front-end will call the `registration` endpoint with the user entered information
  * The API will return success or failure

```shell
curl -X POST -d \
  "user[name]='Test User'&user[phone]=911234554321&user[password]=secret1234 \
  &user[otp]=321721" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration
```

```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "name": "Test User",
        "phone": "911234554321",
        "password": "secret1234",
        "otp": "321721"
    }
}
```

> The above query returns JSON structured like this:

```json
{
    "data": {
        "access_token": "AUTH_TOKEN",
        "token_expiry_time": "2020-07-13T16:22:53.678465Z",
        "renewal_token": "RENEW_TOKEN"
    }
}
```

Glific expects for the auth token to be included in all API requests to the server in a header
that looks like the following:

`Authorization: AUTH_TOKEN`


#
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
{"data":
  {
    "data": {
          "access_token": "AUTH_TOKEN",
          "token_expiry_time": "2020-07-13T16:22:53.678465Z",
          "renewal_token": "RENEW_TOKEN"
      }
  }
}
```

## Renew an existing session

```shell
curl -X POST -H "Authorization: RENEW_TOKEN" \
  http://localhost:4000/api/v1/session/renew
```

> The above query returns JSON structured like this:

```json
{"data":
  {
    "data": {
          "access_token": "AUTH_TOKEN",
          "token_expiry_time": "2020-07-13T16:22:53.678465Z",
          "renewal_token": "RENEW_TOKEN"
      }
  }
}
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

## reset password

The typical forgot password flow will be something like:

  * The caller will call the `send_otp` request with a `Phone Number`
  * On successful confirmation of the delivery of `send_otp`, the front-end will display new password entry screen
  * User enters: `OTP`, `Phone Number` and `New Password`

```shell
curl -X POST -d \
  "user[phone]=911234554321&user[new_password]=secret1234 \
  &user[otp]=321721" \
  http://YOUR_HOSTNAME_AND_PORT/api/v1/registration/reset-password
```

```javascript
If you are using axios or other libraries, send the following in the BODY of a POST request

{
    "user": {
        "phone": "911234554321",
        "password": "secret1234",
        "otp": "321721"
    }
}
```

> The above query returns JSON structured like this:

```json
{
    "data": {
        "access_token": "AUTH_TOKEN",
        "token_expiry_time": "2020-07-13T16:22:53.678465Z",
        "renewal_token": "RENEW_TOKEN"
    }
}
```
