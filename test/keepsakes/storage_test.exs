defmodule Keepsakes.StorageTest do
  use ExUnit.Case, async: true

  alias Keepsakes.Storage
  alias Keepsakes.Storage.{Local, S3}

  describe "key validation" do
    test "accepts nested keys and rejects traversal" do
      assert Storage.valid_key?("users/abc-123/memories/m1/w2400.webp")
      refute Storage.valid_key?("../etc/passwd")
      refute Storage.valid_key?("users/../../secret")
      refute Storage.valid_key?("/absolute/path")
      refute Storage.valid_key?("has space.jpg")
      refute Storage.valid_key?(nil)
    end

    test "facade refuses invalid keys" do
      assert {:error, :invalid_key} = Storage.put("../x", "data")
      assert {:error, :invalid_key} = Storage.get("../x")
      refute Storage.exists?("../x")
    end
  end

  describe "Local adapter" do
    setup do
      root = Path.join(System.tmp_dir!(), "ks-storage-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(root) end)
      %{config: [adapter: Local, root: root]}
    end

    test "put/get/exists?/delete round trip", %{config: config} do
      key = "users/u1/a.txt"

      assert :ok = Local.put(config, key, "hello", [])
      assert Local.exists?(config, key)
      assert {:ok, "hello"} = Local.get(config, key)
      assert :ok = Local.delete(config, key)
      refute Local.exists?(config, key)
      assert {:error, :not_found} = Local.get(config, key)
      assert :ok = Local.delete(config, key)
    end

    test "put/4 copies from a file", %{config: config} do
      source = Path.join(config[:root], "src.bin")
      File.mkdir_p!(config[:root])
      File.write!(source, "file body")

      assert :ok = Local.put(config, "copied/file.bin", {:file, source}, [])
      assert {:ok, "file body"} = Local.get(config, "copied/file.bin")
    end

    test "list/2 returns keys under a prefix", %{config: config} do
      :ok = Local.put(config, "users/u1/a.jpg", "a", [])
      :ok = Local.put(config, "users/u1/memories/m1/w480.webp", "b", [])
      :ok = Local.put(config, "users/u2/c.jpg", "c", [])

      assert {:ok, ["users/u1/a.jpg", "users/u1/memories/m1/w480.webp", "users/u2/c.jpg"]} =
               Local.list(config, "")

      assert {:ok, ["users/u2/c.jpg"]} = Local.list(config, "users/u2/")
    end

    test "url/3 issues a signed token that verifies and expires", %{config: config} do
      "/media/" <> token = Local.url(config, "users/u1/a.jpg", expires_in: 60)
      assert {:ok, "users/u1/a.jpg"} = Local.verify_token(token)

      "/media/" <> expired = Local.url(config, "users/u1/a.jpg", expires_in: -1)
      assert {:error, :expired} = Local.verify_token(expired)

      assert {:error, :invalid} = Local.verify_token("tampered")
    end
  end

  describe "S3 adapter" do
    setup do
      config = [
        adapter: S3,
        bucket: "keepsakes-test",
        endpoint_url: "https://acct.r2.cloudflarestorage.com",
        region: "auto",
        access_key_id: "AKIDTEST",
        secret_access_key: "secret",
        req_options: [plug: {Req.Test, S3}, retry: false]
      ]

      %{config: config}
    end

    test "put/4 sends a signed PUT with content type", %{config: config} do
      Req.Test.stub(S3, fn conn ->
        assert conn.method == "PUT"
        assert conn.request_path == "/keepsakes-test/users/u1/a.webp"
        assert ["image/webp"] = Plug.Conn.get_req_header(conn, "content-type")
        assert [auth] = Plug.Conn.get_req_header(conn, "authorization")
        assert auth =~ "AWS4-HMAC-SHA256 Credential=AKIDTEST/"
        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert :ok = S3.put(config, "users/u1/a.webp", "bytes", content_type: "image/webp")
    end

    test "get/2 maps 404 to :not_found", %{config: config} do
      Req.Test.stub(S3, &Plug.Conn.send_resp(&1, 404, ""))
      assert {:error, :not_found} = S3.get(config, "missing.jpg")
    end

    test "get/2 returns the body", %{config: config} do
      Req.Test.stub(S3, &Plug.Conn.send_resp(&1, 200, "jpeg-bytes"))
      assert {:ok, "jpeg-bytes"} = S3.get(config, "users/u1/a.jpg")
    end

    test "delete/2 treats 204 and 404 as success", %{config: config} do
      Req.Test.stub(S3, &Plug.Conn.send_resp(&1, 204, ""))
      assert :ok = S3.delete(config, "a.jpg")

      Req.Test.stub(S3, &Plug.Conn.send_resp(&1, 404, ""))
      assert :ok = S3.delete(config, "a.jpg")
    end

    test "list/2 follows continuation tokens", %{config: config} do
      Req.Test.stub(S3, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)
        assert conn.request_path == "/keepsakes-test"
        assert %{"list-type" => "2", "prefix" => "users/"} = conn.query_params

        body =
          case conn.query_params["continuation-token"] do
            nil ->
              "<ListBucketResult><IsTruncated>true</IsTruncated>" <>
                "<NextContinuationToken>t2</NextContinuationToken>" <>
                "<Contents><Key>users/a.jpg</Key></Contents>" <>
                "<Contents><Key>users/b.jpg</Key></Contents></ListBucketResult>"

            "t2" ->
              "<ListBucketResult><IsTruncated>false</IsTruncated>" <>
                "<Contents><Key>users/c.jpg</Key></Contents></ListBucketResult>"
          end

        conn
        |> Plug.Conn.put_resp_content_type("application/xml")
        |> Plug.Conn.send_resp(200, body)
      end)

      assert {:ok, ["users/a.jpg", "users/b.jpg", "users/c.jpg"]} = S3.list(config, "users/")
    end

    test "url/3 presigns against the custom endpoint", %{config: config} do
      url = S3.url(config, "users/u1/a.jpg", expires_in: 300)

      assert url =~ "https://acct.r2.cloudflarestorage.com/keepsakes-test/users/u1/a.jpg?"
      assert url =~ "X-Amz-Expires=300"
      assert url =~ "X-Amz-Signature="
    end
  end
end
