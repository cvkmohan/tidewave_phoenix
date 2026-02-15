defmodule Tidewave.MCP.Tools.Logs do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_logs",
        description: """
        Returns all log output, excluding logs that were caused by other tool calls.

        Use this tool to check for request logs or potentially logged errors.

        TIP: To avoid seeing stale errors from previous runs, use the `since` parameter.
        First call project_eval with `DateTime.utc_now() |> to_string()` to get a timestamp,
        perform your action, then call get_logs with that timestamp as `since`.

        PREFER using smoke_test or eval_with_logs instead — they automatically scope
        logs to a specific operation and avoid stale log noise entirely.
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
              description:
                "Only return logs after this ISO8601 timestamp. " <>
                  "Filters out stale logs from previous operations. " <>
                  "Format: \"2026-02-14T10:30:00Z\". " <>
                  "Get current time with project_eval: DateTime.utc_now() |> to_string()"
            }
          }
        },
        callback: &get_logs/1
      }
    ]
  end

  def get_logs(args) do
    case args do
      %{"tail" => n} ->
        opts =
          [
            grep: Map.get(args, "grep"),
            level: Map.get(args, "level"),
            since: parse_since(Map.get(args, "since"))
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        {:ok, Enum.join(Tidewave.MCP.Logger.get_logs(n, opts), "\n")}

      _ ->
        {:error, :invalid_arguments}
    end
  end

  defp parse_since(nil), do: nil

  defp parse_since(since_str) when is_binary(since_str) do
    case DateTime.from_iso8601(since_str) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
end
