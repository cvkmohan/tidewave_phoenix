defmodule TidewaveTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  @moduletag :capture_log

  test "/mcp refuses requests with an origin header" do
    conn =
      conn(:post, "/tidewave/mcp")
      |> put_req_header("origin", "http://localhost:4001")
      |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 403
  end

  test "/ is a local MCP status page with no remote assets" do
    conn = conn(:get, "/tidewave") |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 200
    assert conn.resp_body == "Tidewave MCP is available at /tidewave/mcp\n"
    refute conn.resp_body =~ "tidewave.ai"
    refute conn.resp_body =~ "<script"
  end

  test "allows requests with no origin header" do
    conn = conn(:post, "/tidewave/mcp") |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 200
    assert conn.resp_body =~ "Could not parse message"
  end

  test "validates content type" do
    assert_raise Plug.Conn.WrapperError, ~r/Plug.Parsers.UnsupportedMediaTypeError/, fn ->
      conn(:post, "/tidewave/mcp")
      |> put_req_header("content-type", "multipart/form-data")
      |> Tidewave.call(Tidewave.init([]))
    end
  end

  test "does not allow remote connections by default" do
    conn =
      conn(:get, "/tidewave")
      |> Map.put(:remote_ip, {192, 168, 1, 1})
      |> Tidewave.call(Tidewave.init([]))

    assert conn.status == 403

    conn =
      conn(:get, "/tidewave")
      |> Map.put(:remote_ip, {192, 168, 1, 1})
      |> Tidewave.call(Tidewave.init(allow_remote_access: true))

    assert conn.status == 200
  end

  test "does not rewrite application response headers or HTML" do
    conn =
      conn(:get, "/foo")
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
      conn = conn(:get, "/tidewave/mcp") |> Tidewave.call(Tidewave.init([]))
      assert conn.status == 405
    end

    test "returns 404 for unknown paths" do
      conn =
        conn(:get, "/tidewave/mcp/.well-known/openid-configuration")
        |> Tidewave.call(Tidewave.init([]))

      assert conn.status == 404
    end
  end

  test "raises when Tidewave runs after request parsing" do
    assert_raise RuntimeError, ~r/run.*too late/, fn ->
      conn(:post, "/tidewave/mcp", %{})
      |> Tidewave.call(Tidewave.init([]))
    end
  end
end
