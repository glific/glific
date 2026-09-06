defmodule Glific.GcsFixtures do
  @moduledoc """
  A real (test-generated) RSA keypair and GCS credential, so signed-URL tests can exercise
  `Glific.GCS.SignedUrl`'s actual `:public_key` signing rather than stubbing it — and so a test
  can independently verify a signature against the public half of the same key.
  """

  alias Glific.Partners

  @doc """
  A fresh 2048-bit RSA keypair as `{private_key_pem, public_key}` — the PEM in the shape a real
  GCP service account key ships (`:public_key` handles either PKCS#1 or PKCS#8 transparently),
  and the public key as the raw `:public_key.verify/4`-ready record.
  """
  @spec generate_rsa_keypair() :: {String.t(), tuple()}
  def generate_rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2_048, 65_537})
    pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    pem = :public_key.pem_encode([pem_entry])

    {:RSAPrivateKey, _version, modulus, exponent, _d, _p, _q, _e1, _e2, _c, _other} = private_key
    {pem, {:RSAPublicKey, modulus, exponent}}
  end

  @doc """
  Configures `organization_id`'s `google_cloud_storage` credential with `bucket` and a service
  account keyed by `email`/`private_key_pem`.
  """
  @spec create_gcs_credential(non_neg_integer(), String.t(), String.t(), String.t()) :: :ok
  def create_gcs_credential(organization_id, bucket, email, private_key_pem) do
    {:ok, _credential} =
      Partners.create_credential(%{
        shortcode: "google_cloud_storage",
        secrets: %{
          "bucket" => bucket,
          "service_account" =>
            Jason.encode!(%{
              "project_id" => "test-project",
              "client_email" => email,
              "private_key" => private_key_pem
            })
        },
        is_active: true,
        organization_id: organization_id
      })

    :ok
  end
end
