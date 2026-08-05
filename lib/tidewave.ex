defmodule Tidewave do
  @moduledoc false
  @behaviour Plug

  @doc """
  Clears all captured logs from the logger buffer.

  This is useful when subsequent log retrievals should contain only fresh
  output from the operation being debugged.
  """
  def clear_logs do
    Tidewave.MCP.Logger.clear_logs()
  end

  @impl true
  def init(opts) do
    %{
      allow_remote_access: Keyword.get(opts, :allow_remote_access, false),
      phoenix_endpoint: nil,
      inspect_opts:
        Keyword.get(opts, :inspect_opts, charlists: :as_lists, limit: 50, pretty: true)
    }
  end

  @impl true
  def call(conn, config) do
    config = %{config | phoenix_endpoint: conn.private[:phoenix_endpoint]}

    conn
    |> validate!()
    |> Plug.Conn.put_private(:tidewave_config, config)
    |> call_tidewave()
  end

  defp call_tidewave(%Plug.Conn{path_info: ["tidewave" | rest]} = conn) do
    conn
    |> Plug.forward(rest, Tidewave.Router, [])
    |> Plug.Conn.halt()
  end

  defp call_tidewave(conn), do: conn

  defp validate!(conn) do
    if live_reload_enabled?(conn) or request_body_parsed?(conn) do
      raise "plug Tidewave is runnning too late, after the request body has been parsed. " <>
              "Make sure to place \"plug Tidewave\" before the \"if code_reloading? do\" block"
    end

    conn
  end

  defp live_reload_enabled?(conn) do
    match?(%{phoenix_live_reload: true}, conn.private)
  end

  defp request_body_parsed?(conn) do
    not match?(%Plug.Conn.Unfetched{}, conn.body_params)
  end
end
