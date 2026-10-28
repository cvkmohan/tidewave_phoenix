defmodule Tidewave.Router do
  @moduledoc false

  use Plug.Router

  import Plug.Conn
  alias Tidewave.MCP

  plug(:match)
  plug(:check_remote_ip)
  plug(:check_host)
  plug(:check_origin)
  plug(:dispatch)

  get "/" do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "Tidewave MCP is available at /tidewave/mcp\n")
    |> halt()
  end

  get "/mcp" do
    Logger.metadata(tidewave_mcp: true)

    conn
    |> send_resp(405, "Method Not Allowed")
    |> halt()
  end

  post "/mcp" do
    Logger.metadata(tidewave_mcp: true)

    opts =
      Plug.Parsers.init(
        parsers: [:json],
        pass: [],
        json_decoder: Jason
      )

    conn
    |> Plug.Parsers.call(opts)
    |> MCP.HTTP.run()
    |> halt()
  end

  match "/*_ignored" do
    Logger.metadata(tidewave_mcp: true)

    conn
    |> send_resp(404, "Not Found")
    |> halt()
  end

  defp check_remote_ip(conn, _opts) do
    cond do
      is_local?(conn.remote_ip) ->
        conn

      conn.private.tidewave_config.allow_remote_access ->
        conn

      true ->
        log_and_send_403(conn, """
        For security reasons, Tidewave does not accept remote connections by default.

        If you really want to allow remote connections, configure Tidewave with the `allow_remote_access: true` option.
        """)
    end
  end

  defp is_local?({127, 0, 0, _}), do: true
  defp is_local?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  defp is_local?({0, 0, 0, 0, 0, 65535, 32512, 1}), do: true
  defp is_local?(_), do: false

  # Validating the Host header protects against DNS rebinding attacks,
  # where a malicious domain resolves to 127.0.0.1 and reaches Tidewave
  # without sending an Origin header.
  defp check_host(conn, _opts) do
    if allowed_host?(conn) do
      conn
    else
      log_and_send_403(conn, """
      For security reasons, Tidewave only accepts requests to the same host your web app is running on.

      If you really want to allow this host, configure the `allowed_origins: [#{inspect("//" <> conn.host)}]` option.
      """)
    end
  end

  defp allowed_host?(conn) do
    host = conn.host |> String.downcase() |> String.trim_leading("[") |> String.trim_trailing("]")

    # IP addresses cannot be rebound and localhost domains resolve to the
    # loopback address in browsers, so they are always allowed. Only hosts
    # are compared, as ports are not relevant to DNS rebinding.
    match?({:ok, _}, :inet.parse_strict_address(String.to_charlist(host))) or
      compare_host?(host, "*.localhost") or
      Enum.any?(allowed_hosts(conn), &compare_host?(host, &1))
  end

  # When no origins are configured, we allow the host of the Phoenix endpoint.
  # If no host can be derived, only IP addresses and localhost are allowed.
  defp allowed_hosts(conn) do
    case conn.private.tidewave_config do
      %{allowed_origins: [_ | _] = allowed_origins} ->
        Enum.map(allowed_origins, & &1.host)

      %{phoenix_endpoint: endpoint} when not is_nil(endpoint) ->
        List.wrap(host_from_endpoint(endpoint))

      _ ->
        []
    end
  end

  defp host_from_endpoint(endpoint) do
    host =
      cond do
        function_exported?(endpoint, :struct_url, 0) -> endpoint.struct_url().host
        function_exported?(endpoint, :config, 1) -> endpoint.config(:url)[:host]
        true -> nil
      end

    host && String.downcase(host)
  end

  defp compare_host?(request_host, "*." <> allowed_host),
    do: request_host == allowed_host or String.ends_with?(request_host, "." <> allowed_host)

  defp compare_host?(request_host, allowed_host),
    do: request_host == allowed_host

  defp check_origin(conn, _opts) do
    case get_req_header(conn, "origin") do
      [] ->
        conn

      _ ->
        log_and_send_403(conn, """
        For security reasons, Tidewave does not accept requests with an origin header.
        """)
    end
  end

  defp log_and_send_403(conn, message) do
    require Logger
    Logger.warning(message)

    conn
    |> send_resp(403, message)
    |> halt()
  end
end
