defmodule Glific.Dialogflow do
  @moduledoc """
  Module to communicate with DialogFlow v2. This module was taken directly from:
  https://github.com/resuelve/flowex/

  I pulled it into our repository since the comments were in Spanish and it did not
  seem to be maintained, that we could not use as is. The dependency list was quite old etc.
  """

  alias Goth.Token

  @doc """
  The request controller which sends and parses requests. We should move this to Tesla
  """
  @spec request(non_neg_integer, atom, String.t(), String.t() | map) :: tuple
  def request(organization_id, method, path, body) do
    %{host: host, id: id, email: email} = project_info(organization_id)

    url = "#{host}/v2beta1/projects/#{id}/locations/global/agent/#{path}"

    case_test = do_request(method, url, body(body), headers(email))

    IO.inspect(case_test)

    case case_test do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        {:ok, Poison.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status in 400..499 ->
        {:error, Poison.decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} when status >= 500 ->
        {:error, Poison.decode!(body)}

      {:error, %Tesla.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  defp do_request(:post, url, body, header), do: Tesla.post(url, body, headers: header)
  defp do_request(_, url, _, _), do: Tesla.get(url)

  # ---------------------------------------------------------------------------
  # Encode body
  # ---------------------------------------------------------------------------
  @spec body(String.t() | map) :: String.t()
  defp body(""), do: ""
  defp body(body), do: Poison.encode!(body)

  # ---------------------------------------------------------------------------
  # Headers for all subsequent API calls
  # ---------------------------------------------------------------------------
  @spec headers(String.t()) :: list
  defp headers(_email) do
    newconfig = %{
  "type" => "service_account",
  "project_id" => "newagent-wtro",
  "private_key_id" => "eb880c7be59aadb37e3878b03c91063f030f373b",
  "private_key" => "-----BEGIN PRIVATE KEY-----\nMIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQC+20c2cT6QNQCW\nHFHkCYQwL0cpxSp4kRCAJU7z5yTh4DGeq6FBCY+51fWu7p5ABJDfTLQqsx0kw7ap\nvOyZNRmhVSCL+KxM02ABD/2ljvVQkO02TSjmKMj8oUxJ18HU+AfelW1M98GPfyGc\nGc5sIxEUxZ4+rG6zQy14N6aCN/LQZXgL+tx0ocrsWxDGfQYTsk3mRWB1wzKs+dHQ\npsZSrxhL7mqTtvCLzpWjv2hBjKu/mRs6XKNTVdtlfv/9KBVEwC0a668SGExo7wq+\nLjMO6zm0giAgUVz23QLZsb5XbAV2VmbnUB3LDVEINzgEuJyHE4yoVrXUEfW/39F7\nwJSVYzOJAgMBAAECggEAHmGooeWACJOvXrXuYUcUiFkWUnNk8eFhx4xo15GtgNlf\n/LqkhkZf3zzMicbJYTZ421sJ+RwfIQmYq8d7wF3AETsMXcu9ndMuHq0teuvZaDRR\n1omM36qRaAnDK6QRYnYDRq7xwcVUxiN+Nauz/OnOH8jfimmHi7i/ZboyItuGJx8h\nHncrwOhCKCiR5BMXV+HzRcuv9/4ecazWBSvsMehmHYCZVw9HFTXcI9L+o1gwssyK\npfbyjJkMLnbXruuRqwVRh9UsdV2knLeiWQ0xYKhu9iD98xDLkweKCrsKsoI662zZ\n7bC4a3GlRJa2o0dwqaJTcFZSo5xKugUX4QeCj5umSwKBgQD3QxcUVlD1mzuQtFqM\n44yj1SumOGOjO2Sp753vUW0Cp6uMTr2Puokv1dPcnvq4MrNhN1+KqY2+go1hWTWS\nn5T1DlolB/KV8EgAw4zs40Df1b/6UVtnFx6zGeHpdcPEVvbF8vwXqJoStl3LZ4P3\n5n/5am1rLUANUd/BCzO3G8MzJwKBgQDFmec/odrsWTca9KCXkVAsfwjsnP+acSu+\nt99MkvEuDD0bAtbl15ERAaHR4YpnmBsM7YPTY6wYVZNmVHXTuAbzES1BMg6ZDYXT\nAf2XJuW1De9oS21mLf6Z5gqEhBfL+7ZQtjq4y/yIQufcF/VlYH5yD79hTXB+R6aS\n9T76IibRzwKBgQCk/6MmEheCXe1YudF3FN2j8jtnd1ed9KNO9zRIH+kDjYnfXigH\nAm5LeoAfSAN86XBkXkQmTtDkoU/g91vVlSIciVBER9JsleQmhlfDOD7xXzz1uFar\nK3V0BMCJPum9Wl7gZy4sR3lRJVrfwhsBUVJyyL9tdsu4V7tdobEH7sHKnwKBgQCR\neE7k6owXyUonHwaG7qR+TXtNbftCQKR6wDS008yYIMxvcTSxenRCd9ggghD5WOI5\nLzYITm1ocL+V6wHfPrBnCzMstuRGSs1FXUbKmwkqtDqWpkjAm4W+2LrPectnEUTT\nwIQUfZ/I1LCKuFyhKFuOLweuY2s4nBkGQWP+k1vOwwKBgHiOsL2R2xN76dkpMdn8\nvr+5yl8Qf26xrXefPQotrBFZmH8DAh8vJyZghjkqg3rgLtyRoGY69DX9jeR3QJe7\nRkSeHsdXzzCdCBLqyVF7WV2yd5i7IYrxgg3WoEHA1DkyGc7Xm0/QQDA7PHyuhtJL\nmQwgKCfez2Y8aAmJ5FJCjFmL\n-----END PRIVATE KEY-----\n",
  "client_email" => "dialogflow-pnfavu@newagent-wtro.iam.gserviceaccount.com",
  "client_id" => "116275873899089733817",
  "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
  "token_uri" => "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url" => "https://www.googleapis.com/robot/v1/metadata/x509/dialogflow-pnfavu%40newagent-wtro.iam.gserviceaccount.com"
}


    newconfig2 =  %{
    "type" => "service_account",
    "project_id" => "bottest-mmhi",
    "private_key_id" => "3a6c31bc016fad5b0813bb9d1c73430733f81037",
    "private_key" => "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQCcEPBpq3o2Egxh +GIwMQioQiLtzUduNHZVgQa7gV6k/zJxa7yFovgerD4fInc+EUXt+L9bywUOtjlM 05wHZhjHnNMQmNmTiLZNw8QYDnWBXgZosz5re/KOm8BWKZ3b96g2MxVKIIC2StFN 7udOBV4caCs86EOG9Uu0s9jacSYmV8InX6MsLhNpE1UaCFDaoGy63LDRKc6HoOaV 3dfceTjhmROSncjGfajRyaK+4hrFCm15YgdqUbGXmcGpoNqs56hylZigrYrnGVSA 7lRTlVfT24u/8RmBiiQt9dXl6GSkR7jVj9voIqMWcIx39KXG8CztF/JC4lNqFC+o KyGb4kuFAgMBAAECggEAQEOfY7vnOp2q+Kqpb/O4/2QgcvCtQb2bnrDfP1XRzbqC IH8/JX5KkoLVn8d295lwRMJBtgA/CGRT6wVWAhvyBzxWE0cFjQFmJFaBCHDnxQod NH7erK7g3gVXqYNAjCQKYaseUKRaq/XaAy/lklSWgLcKWu2/ZLLcZkAKg0TFc1LZ gXrtbS3VJpkTyEmSLLEW9OWBqkxtTqnm8iJsgn1iEKfibXQJXPA5o9QyIBZG5ix0 GBTS+Zm11CLcgoQ6Cii+2zLPN8F9X5uEgEFdeOJakQXXFSFi+0fRZQlnRnELb8sN nd0HyO1bj27eY5e31eJZoYvo8WwlF93tUeiBS2/+PwKBgQDbJT5J4IxmQ456aUWp PMT6PwKOuj5b09NnCHK7pkgZzk8jwe1yoLq8ieicJ2iBYMNP4JMi7t4DrEXEBeoS ztP3zPm3llSmAHtqLu/09Y7638owzSCPF/Gy5E01M1zi+ogK6TBO9Q8VNmGqM1jQ Bp8j1lt5oKaoo+FjTZMSXex1mwKBgQC2T/mQgRa1oyvcQcmDfs5pZp9MjAa6vDIw UYEwIjIo3CozJ5oZCZiSK62SqaC4czhRvgrZgxsB73n8iRfo3wNqkC7E8QzdlgcV VAea7wTJ8lBQeKMXUvLy7YfIkJTLbyqqd2Wvz9HJTIY45YXFS+GARlQF85wdBrRe a2orAj3lXwKBgQCvNszhpo666QLO7sKKuJLJfn2d/l0DcI7TD1ckn6OANoriDRi7 kLUdL6pyx7Nv1hzzDZy2zoNmLmQtgYkQdpvVweZbGfAeNb53PIYQthEWlr2DXU7N +hf+rzjn82Qt+p+xEZbVWmwvyqY1vg4hbVnp/mZvDbqSlU0M56ZShhQcRwKBgQCT Oxbyai2q1nGPWNmihf+wAx5WtSaiG2X0u323H4aelN7HnQ3HdoZuVTPBo5eWHga3 jOA6NLTU5U8AcL6MY73gizwZ9AlN0eE6ijfyGWEmrbfKpQIgze5B3S2w/YIMoGQ2 cmH+j7h99nzW6hUT9mnQK/ujKs9Caa20Ks78mLzfxQKBgQC2k7iTWckch7rGtN7f 6k3WyFSdIltQXRNSEuXxoD3ZrHTEEk/32zimOyHaM0jCFlw6eyqP8FsJ8UzmpdCN g3PWI7DnldWhJINv0MlKprPX4k6fBQnpMnu84SKsxvzT7J9RRS2aWfVOJjUamy3z xmf4MRkXIBRYKiVmUF1G7tH2iQ==\n-----END PRIVATE KEY-----\n",
    "client_email" => "testing@bottest-mmhi.iam.gserviceaccount.com",
    "client_id" => "108558728464118950377",
    "auth_uri" => "https://accounts.google.com/o/oauth2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token",
    "auth_provider_x509_cert_url" => "https://www.googleapis.com/oauth2/v1/certs",
    "client_x509_cert_url" => "https://www.googleapis.com/robot/v1/metadata/x509/testing%40bottest-mmhi.iam.gserviceaccount.com"
  }


    Goth.Config.add_config(newconfig)
    Goth.Config.add_config(newconfig2)

    IO.inspect("Hello Sir")
    IO.inspect(Goth.Config.get("json"))
    IO.inspect(Goth.Config.get("testing@bottest-mmhi.iam.gserviceaccount.com", "private_key_id"))
    IO.inspect(Goth.Config.get("testing@bottest-mmhi.iam.gserviceaccount.com", "project_id"))



    #{:ok, token} = Token.for_scope({"dialogflow-pnfavu@newagent-wtro.iam.gserviceaccount.com", "https://www.googleapis.com/auth/cloud-platform"})

    {:ok, token} = Token.for_scope({"testing@bottest-mmhi.iam.gserviceaccount.com", "https://www.googleapis.com/auth/cloud-platform"})

    #{:ok, token} = Token.for_scope("https://www.googleapis.com/auth/cloud-platform")

    IO.inspect(token)
    [
      {"Authorization", "Bearer #{token.token}"},
      {"Content-Type", "application/json"}
    ]
  end

  # ---------------------------------------------------------------------------
  # Get the project details needed for authentication and to send via the API
  # ---------------------------------------------------------------------------
  @spec project_info(non_neg_integer) :: %{
          :host => String.t(),
          :id => String.t(),
          :email => String.t()
        }
  defp project_info(organization_id) do
    case Glific.Partners.get_credential(%{
           organization_id: 2,
           shortcode: "dialogflow"
         }) do
      {:ok, credential} ->
        %{
          host: credential.keys["host"],
          id: credential.secrets["project_id"],
          email: credential.secrets["project_email"]
        }

      {:error, _} ->
        %{
          host: nil,
          id: nil,
          email: nil
        }
    end
  end
end
