defmodule Tidewave.MCP.Tools.Logs do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_logs",
        description: """
        Returns all log output, excluding logs that were caused by other tool calls.

        Use this tool to check for request logs or potentially logged errors.

        Pass an ISO 8601 timestamp as `since` to return only logs captured after
        that point. This scopes diagnostics without clearing logs used by another
        agent or browser session.
        """,
        inputSchema: %{
          type: "object",
          required: ["tail"],
          properties: %{
            tail: %{
              type: "integer",
              description: "The number of log entries to return from the end of the log"
            },
            grep: %{
              type: "string",
              description:
                "Filter logs with the given regular expression (case insensitive). E.g. \"timeout\" to find timeout-related messages"
            },
            level: %{
              type: "string",
              enum: ~w(emergency alert critical error warning notice info debug),
              description: "Filter logs by log level (e.g. \"error\" for error logs only)"
            },
            since: %{
              type: "string",
              description: "Only return logs captured after this ISO 8601 timestamp"
            }
          }
        },
        annotations: %{readOnlyHint: true},
        callback: &get_logs/1
      }
    ]
  end

  def get_logs(args) do
    case args do
      %{"tail" => n} ->
        with {:ok, since} <- parse_since(Map.get(args, "since")) do
          opts =
            [grep: Map.get(args, "grep"), level: Map.get(args, "level"), since: since]
            |> Enum.reject(fn {_k, v} -> is_nil(v) end)

          {:ok, Enum.join(Tidewave.MCP.Logger.get_logs(n, opts), "\n")}
        end

      _ ->
        {:error, :invalid_arguments}
    end
  end

  defp parse_since(nil), do: {:ok, nil}

  defp parse_since(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, _reason} -> {:error, "Invalid `since` timestamp; expected ISO 8601"}
    end
  end

  defp parse_since(_value), do: {:error, "Invalid `since` timestamp; expected ISO 8601"}
end
