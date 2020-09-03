use Mix.Config

# config dialogflow
config :glific,
  dialogflow_url: "https://dialogflow.clients6.google.com",
  dialogflow_project_id: "newagent-wtro",
  dialogflow_project_email: "dialogflow-pnfavu@newagent-wtro.iam.gserviceaccount.com"

# config goth and fake it while we are still developing

fake_goth_json = """
{
"project_id": "DOES NOT EXISTS",
"private_key_id": "DOES NOT EXIST",
"private_key": "INVALID PRIVATE KEY"
}
"""

# for now this is optional, so we check for file exists, need
# a more robust solution going forward
goth_json =
  if File.exists?("config/.dialogflow.credentials.json"),
    do: File.read!("config/.dialogflow.credentials.json"),
    else: fake_goth_json

# config goth
config :goth,
  json: goth_json
