defmodule Glific.PublicUrlTest do
  use ExUnit.Case, async: true

  alias Glific.PublicUrl

  test "accepts http and https URLs on public hosts" do
    assert PublicUrl.public?("https://docs.google.com/spreadsheets/d/abc/export?format=csv")
    assert PublicUrl.public?("http://8.8.8.8/contacts.csv")
    assert PublicUrl.public?("https://[2001:4860:4860::8888]/contacts.csv")
  end

  test "rejects hosts that resolve to internal addresses" do
    for url <- [
          "http://localhost:4000/contacts.csv",
          "http://internal.example/contacts.csv",
          "http://127.0.0.1/contacts.csv",
          "http://0.0.0.0/contacts.csv",
          "http://10.1.2.3/contacts.csv",
          "http://100.64.0.1/contacts.csv",
          "http://169.254.169.254/latest/meta-data",
          "http://172.16.0.1/contacts.csv",
          "http://192.168.1.1/contacts.csv",
          "http://224.0.0.1/contacts.csv",
          "http://[::1]/contacts.csv",
          "http://[fe80::1]/contacts.csv",
          "http://[fd00::1]/contacts.csv",
          "http://[::ffff:127.0.0.1]/contacts.csv"
        ] do
      refute PublicUrl.public?(url), url
    end
  end

  test "rejects non-http schemes and malformed input" do
    refute PublicUrl.public?("file:///etc/passwd")
    refute PublicUrl.public?("ftp://8.8.8.8/contacts.csv")
    refute PublicUrl.public?("not a url")
    refute PublicUrl.public?(nil)
  end
end
