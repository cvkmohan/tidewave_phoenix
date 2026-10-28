defmodule TidewaveTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  @moduletag :capture_log

  test "/mcp refuses requests with an origin header" do
    conn =
      conn(:post, "http://localhost/tidewave/mcp")
      |> put_req_header("origin", "http://localhost:4001")
      |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 403
  end

  test "/ is a local MCP status page with no remote assets" do
    conn = conn(:get, "http://localhost/tidewave") |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 200
    assert conn.resp_body == "Tidewave MCP is available at /tidewave/mcp\n"
    refute conn.resp_body =~ "tidewave.ai"
    refute conn.resp_body =~ "<script"
  end

  test "allows requests with no origin header" do
    conn = conn(:post, "http://localhost/tidewave/mcp") |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Could not parse message"
  end

  describe "host check" do
    defmodule ExampleEndpoint do
      def struct_url, do: URI.parse("http://example.com")
    end

    defmodule NilHostEndpoint do
      def config(:url), do: []
    end

    test "always allows IP addresses and localhost domains" do
      for host <- ["127.0.0.1", "[::1]", "192.168.1.1", "localhost", "admin.localhost"] do
        conn = conn(:get, "http://#{host}:4000/tidewave") |> Tidewave.call(Tidewave.init([]))
        assert conn.status == 200, "expected #{host} to be allowed"
      end
    end

    test "allows the phoenix endpoint url host" do
      conn =
        conn(:get, "http://Example.com/tidewave")
        |> put_private(:phoenix_endpoint, ExampleEndpoint)
        |> Tidewave.call(Tidewave.init([]))

      assert conn.status == 200
    end

    test "allows hosts from allowed_origins, ignoring scheme and port" do
      opts = Tidewave.init(allowed_origins: ["https://example.com:9898", "//*.test"])

      for url <- ["http://example.com:4000/tidewave", "http://app.test/tidewave"] do
        assert (conn(:get, url) |> Tidewave.call(opts)).status == 200, url
      end
    end

    test "rejects other hosts on all routes" do
      for {method, path} <- [get: "", get: "/mcp", post: "/mcp", get: "/other"] do
        conn =
          conn(method, "http://evil.com:4000/tidewave#{path}")
          |> put_private(:phoenix_endpoint, ExampleEndpoint)
          |> Tidewave.call(Tidewave.init([]))

        assert conn.status == 403
        assert conn.resp_body =~ ~s|allowed_origins: ["//evil.com"]|
      end
    end

    test "rejects other hosts without a phoenix endpoint host or allowed origins" do
      for endpoint <- [nil, NilHostEndpoint] do
        conn =
          conn(:get, "http://myapp.test/tidewave")
          |> put_private(:phoenix_endpoint, endpoint)
          |> Tidewave.call(Tidewave.init([]))

        assert conn.status == 403
      end
    end

    test "rejects an invalid allowed_origins value" do
      assert_raise ArgumentError, ~r/invalid :allowed_origins/, fn ->
        Tidewave.init(allowed_origins: ["not an origin"])
      end
    end

    test "still rejects an Origin header on an allowed host" do
      conn =
        conn(:post, "http://localhost/tidewave/mcp")
        |> put_req_header("origin", "http://localhost")
        |> Tidewave.call(Tidewave.init([]))

      assert conn.status == 403
    end
  end

  test "validates content type" do
    assert_raise Plug.Conn.WrapperError, ~r/Plug.Parsers.UnsupportedMediaTypeError/, fn ->
      conn(:post, "http://localhost/tidewave/mcp")
      |> put_req_header("content-type", "multipart/form-data")
      |> Tidewave.call(Tidewave.init([]))
    end
  end

  test "does not allow remote connections by default" do
    conn =
      conn(:get, "http://localhost/tidewave")
      |> Map.put(:remote_ip, {192, 168, 1, 1})
      |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 403

    conn =
      conn(:get, "http://localhost/tidewave")
      |> Map.put(:remote_ip, {192, 168, 1, 1})
      |> Tidewave.call(Tidewave.init(allow_remote_access: true))

    assert conn.status == 200
  end

  test "does not rewrite application response headers or HTML" do
    conn =
      conn(:get, "http://localhost/foo")
      |> put_resp_header("content-security-policy", "default-src 'self'; frame-ancestors 'none'")
      |> put_resp_header("x-frame-options", "DENY")
      |> Tidewave.call(Tidewave.init([]))
      |> send_resp(200, "<html><head></head><body>local</body></html>")

    assert get_resp_header(conn, "content-security-policy") == [
             "default-src 'self'; frame-ancestors 'none'"
           ]

    assert get_resp_header(conn, "x-frame-options") == ["DENY"]
    refute conn.resp_body =~ "tidewave.ai"
  end

  describe "/mcp" do
    test "returns 405 for GET" do
      conn = conn(:get, "http://localhost/tidewave/mcp") |> Tidewave.call(Tidewave.init([]))
      assert conn.status == 405
    end

    test "returns 404 for unknown paths" do
      conn =
        conn(:get, "http://localhost/tidewave/mcp/.well-known/openid-configuration")
        |> Tidewave.call(Tidewave.init([]))

      assert conn.status == 404
    end
  end

  test "raises when Tidewave runs after request parsing" do
    assert_raise RuntimeError, ~r/run.*too late/, fn ->
      conn(:post, "http://localhost/tidewave/mcp", %{})
      |> Tidewave.call(Tidewave.init([]))
    end
  end
end
