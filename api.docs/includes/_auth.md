# Authentication

Authorization in Glific is still at a prototype stage and is not currently enforced by the system.
We do **not** use GraphQL for authorization, but use REST to generate and renew tokens. The
authentication tokens should be included in all GraphQL requests. This section will be expanded to also
include roles and permissions. User management will be done via GraphQL

The main API endpoints are listed below

## Create a new user
```shell
curl -X POST -d
  "user[phone]=test@example.com&user[password]=secret1234 \
  &user[password_confirmation]=secret1234"
  http://glific.io/api/v1/registration
```

> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```

Glific expects for the auth token to be included in all API requests to the server in a header
that looks like the following:

`Authorization: AUTH_TOKEN`


## Send an OTP request to verify a phone number
(this needs to be protected by some form of access control)

```shell
curl -X POST -d
  "user[phone]=test@example.com"
  http://glific.io/api/v1/registration/send_otp
```

> The above query returns JSON structured like this:

```json
{"data": {"phone": phone, "otp": otp,
          "message": "OTP #{otp} sent successfully to #{phone}"}}
```

## Create a new session for an existing user

```shell
curl -X POST -d
  "user[phone]=test@example.com&user[password]=secret1234"
  http://glific.io/api/v1/session
```

> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```

## Renew an existing session

```shell
curl -X POST -H "Authorization: RENEW_TOKEN"
  http://localhost:4000/api/v1/session/renew
```

> The above query returns JSON structured like this:

```json
{"data":{"renewal_token":"RENEW_TOKEN","access_token":"AUTH_TOKEN"}}
```
## Delete an existing session

```shell
curl -X DELETE -H "Authorization: AUTH_TOKEN"
  http://localhost:4000/api/v1/session
```

> The above query returns JSON structured like this:

```json
{"data":{}}
```
