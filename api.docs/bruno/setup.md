# Bruno API Collection Setup Guide

## Prerequisites

1. Ensure you have Bruno installed on your system. If not, download and install it from [Bruno's official website](https://www.usebruno.com/downloads).

2. Access to the Bruno API collection and environment files.

## Steps

### 1. Import Bruno API Collection

```plaintext
1. Open Bruno.
2. Click on "Import Collection".
3. Choose "Bruno Collection".
4. Choose file `/api.docs/bruno/glific_api` in the glific backend repository.
5. Click "Import" to add the collection to your Bruno workspace.
```

### 2. Setting up Bruno Environment

1. Set up the a new environment or change the environment to 'Globals'.
2. Variables `api_url` and `auth_token` should be present in the environment.
3. `api_url` is already set up if you have changed it to 'Globals' else the value should be `https://api.staging.tides.coloredcow.com/api`.
4. `auth_token` will be automatically setup when you run the Login Api in your bruno environment.

### 3. Collaborating using Bruno

1. To create a new request or modify an existing one, simply use the Bruno desktop app. 

2. Once you've made the necessary changes in the Bruno app, don't forget to push them to Github like you normally would. This ensures that all your updates become visible in the repository for everyone to access and collaborate on.



