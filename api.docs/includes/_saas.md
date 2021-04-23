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
  "messages": {email: "email is invalid", shortcode: "shortcode already taken"}
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
