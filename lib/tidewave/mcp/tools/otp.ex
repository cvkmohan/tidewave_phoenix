defmodule Tidewave.MCP.Tools.Otp do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_sup_tree",
        description: """
        Returns the supervision tree of the running application.

        Shows supervisors, workers, their restart strategies, and PIDs in a tree format.
        Useful for understanding the application's process architecture.

        Optionally provide a supervisor name to show only a subtree.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            supervisor: %{
              type: "string",
              description:
                "Optional supervisor module or registered name to start from (e.g., \"MyApp.Supervisor\"). Defaults to all application supervisors."
            },
            max_depth: %{
              type: "integer",
              description: "Maximum depth to traverse (default: 10)"
            }
          }
        },
        callback: &get_sup_tree/1
      },
      %{
        name: "get_top_processes",
        description: """
        Returns the top processes in the BEAM VM sorted by resource usage.

        Shows process name/pid, memory, message queue length, reductions, and current function.
        Useful for identifying memory leaks, stuck processes, or performance bottlenecks.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            sort_by: %{
              type: "string",
              enum: ["memory", "reductions", "message_queue_len"],
              description: "Sort criteria (default: \"memory\")"
            },
            limit: %{
              type: "integer",
              description: "Number of processes to return (default: 20)"
            }
          }
        },
        callback: &get_top_processes/1
      },
      %{
        name: "get_process_info",
        description: """
        Returns detailed information about a specific process.

        Shows memory, message queue, current function, links, monitors, status, and
        optionally the process state. Provide a registered name or PID string.
        """,
        inputSchema: %{
          type: "object",
          required: ["process"],
          properties: %{
            process: %{
              type: "string",
              description:
                "Process identifier - a registered name (e.g., \"MyApp.Repo\") or PID string (e.g., \"0.123.0\")"
            },
            include_state: %{
              type: "boolean",
              description:
                "Include process state via :sys.get_state (default: false, may timeout for busy processes)"
            }
          }
        },
        callback: &get_process_info/1
      }
    ]
  end

  # ============================================================================
  # get_sup_tree
  # ============================================================================

  def get_sup_tree(args) do
    max_depth = Map.get(args, "max_depth", 10)

    case Map.get(args, "supervisor") do
      nil ->
        trees =
          for {app, _, _} <- Application.started_applications(),
              pid = find_app_supervisor(app),
              pid != nil do
            "## #{app}\n\n#{format_tree(pid, 0, max_depth)}"
          end

        if Enum.empty?(trees) do
          {:error, "No application supervisors found"}
        else
          {:ok, Enum.join(trees, "\n\n")}
        end

      name ->
        case resolve_process(name) do
          {:ok, pid} ->
            {:ok, "# #{name}\n\n#{format_tree(pid, 0, max_depth)}"}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # get_sup_tree always receives a map from MCP dispatch

  defp find_app_supervisor(app) do
    case Application.get_application(app) do
      ^app ->
        # Try the master pid from application controller
        case :application_controller.get_master(app) do
          :undefined ->
            nil

          master_pid ->
            # The master's first child is typically the top supervisor
            case Process.info(master_pid, :links) do
              {:links, links} ->
                Enum.find(links, fn pid ->
                  is_pid(pid) and pid != self() and is_supervisor?(pid)
                end)

              _ ->
                nil
            end
        end

      _ ->
        nil
    end
  end

  defp is_supervisor?(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$initial_call") do
          {:supervisor, _, _} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp format_tree(pid, depth, max_depth) when depth >= max_depth do
    "#{indent(depth)}#{format_pid(pid)} ... (max depth reached)"
  end

  defp format_tree(pid, depth, max_depth) when is_pid(pid) do
    case Supervisor.which_children(pid) do
      children when is_list(children) ->
        header = "#{indent(depth)}#{format_pid(pid)} (supervisor)"

        child_lines =
          Enum.map(children, fn {id, child_pid, type, modules} ->
            id_str = if is_atom(id), do: inspect(id), else: "#{inspect(id)}"
            modules_str = if modules == :dynamic, do: "dynamic", else: inspect(modules)

            case {type, child_pid} do
              {:supervisor, pid} when is_pid(pid) ->
                "#{indent(depth + 1)}[#{id_str}] #{modules_str}\n#{format_tree(pid, depth + 2, max_depth)}"

              {:worker, pid} when is_pid(pid) ->
                "#{indent(depth + 1)}[#{id_str}] #{format_pid(pid)} (worker) #{modules_str}"

              {type, :restarting} ->
                "#{indent(depth + 1)}[#{id_str}] (restarting #{type})"

              {type, :undefined} ->
                "#{indent(depth + 1)}[#{id_str}] (not started #{type})"

              {type, _} ->
                "#{indent(depth + 1)}[#{id_str}] (#{type})"
            end
          end)

        Enum.join([header | child_lines], "\n")

      _ ->
        "#{indent(depth)}#{format_pid(pid)} (worker)"
    end
  end

  defp format_tree(other, depth, _max_depth) do
    "#{indent(depth)}#{inspect(other)}"
  end

  # ============================================================================
  # get_top_processes
  # ============================================================================

  def get_top_processes(args) do
    sort_by = Map.get(args, "sort_by", "memory") |> String.to_existing_atom()
    limit = Map.get(args, "limit", 20)

    info_keys = [:registered_name, :memory, :reductions, :message_queue_len, :current_function]

    processes =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, info_keys) do
          nil -> nil
          info -> {pid, info}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(fn {_pid, info} -> Keyword.get(info, sort_by, 0) end, :desc)
      |> Enum.take(limit)

    header = "# Top #{limit} Processes by #{sort_by}\n\n"

    header <>
      "| # | Process | Memory | Reductions | MsgQ | Current Function |\n" <>
      "|---|---------|--------|------------|------|------------------|\n"

    rows =
      processes
      |> Enum.with_index(1)
      |> Enum.map(fn {{pid, info}, idx} ->
        name =
          case Keyword.get(info, :registered_name) do
            [] -> inspect(pid)
            name -> inspect(name)
          end

        memory = format_bytes(Keyword.get(info, :memory, 0))
        reds = Keyword.get(info, :reductions, 0) |> format_number()
        msgq = Keyword.get(info, :message_queue_len, 0)

        current_fn =
          case Keyword.get(info, :current_function) do
            {m, f, a} -> "#{inspect(m)}.#{f}/#{a}"
            other -> inspect(other)
          end

        "| #{idx} | #{name} | #{memory} | #{reds} | #{msgq} | #{current_fn} |"
      end)

    total = length(Process.list())

    result =
      header <>
        "| # | Process | Memory | Reductions | MsgQ | Current Function |\n" <>
        "|---|---------|--------|------------|------|------------------|\n" <>
        Enum.join(rows, "\n") <>
        "\n\nTotal processes: #{total}"

    {:ok, result}
  end

  # get_top_processes always receives a map from MCP dispatch

  # ============================================================================
  # get_process_info
  # ============================================================================

  def get_process_info(%{"process" => process_str} = args) do
    include_state = Map.get(args, "include_state", false)

    case resolve_process(process_str) do
      {:ok, pid} ->
        info_keys = [
          :registered_name,
          :memory,
          :message_queue_len,
          :reductions,
          :current_function,
          :initial_call,
          :status,
          :links,
          :monitors,
          :monitored_by,
          :trap_exit,
          :dictionary
        ]

        case Process.info(pid, info_keys) do
          nil ->
            {:error, "Process #{process_str} is no longer alive"}

          info ->
            name =
              case Keyword.get(info, :registered_name) do
                [] -> inspect(pid)
                name -> inspect(name)
              end

            initial_call =
              case Keyword.get(info, :dictionary, []) |> Keyword.get(:"$initial_call") do
                {m, f, a} -> "#{inspect(m)}.#{f}/#{a}"
                nil -> format_mfa(Keyword.get(info, :initial_call))
              end

            current_fn = format_mfa(Keyword.get(info, :current_function))

            links =
              Keyword.get(info, :links, [])
              |> Enum.map(&format_pid/1)
              |> Enum.join(", ")

            monitors =
              Keyword.get(info, :monitors, [])
              |> Enum.map(fn
                {:process, pid} -> format_pid(pid)
                other -> inspect(other)
              end)
              |> Enum.join(", ")

            monitored_by =
              Keyword.get(info, :monitored_by, [])
              |> Enum.map(&format_pid/1)
              |> Enum.join(", ")

            result = """
            # Process: #{name}

            * PID: #{inspect(pid)}
            * Status: #{Keyword.get(info, :status)}
            * Memory: #{format_bytes(Keyword.get(info, :memory, 0))}
            * Reductions: #{format_number(Keyword.get(info, :reductions, 0))}
            * Message queue: #{Keyword.get(info, :message_queue_len, 0)}
            * Trap exit: #{Keyword.get(info, :trap_exit, false)}
            * Initial call: #{initial_call}
            * Current function: #{current_fn}
            * Links: #{if links == "", do: "none", else: links}
            * Monitors: #{if monitors == "", do: "none", else: monitors}
            * Monitored by: #{if monitored_by == "", do: "none", else: monitored_by}
            """

            result =
              if include_state do
                state =
                  try do
                    :sys.get_state(pid, 5000) |> inspect(pretty: true, limit: 50)
                  catch
                    _, _ -> "(unable to get state - process may not support :sys protocol)"
                  end

                result <> "\n## State\n\n```elixir\n#{state}\n```"
              else
                result
              end

            {:ok, String.trim(result)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_process_info(_), do: {:error, :invalid_arguments}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp resolve_process(name) when is_binary(name) do
    # Try as PID string first (e.g., "0.123.0")
    case parse_pid_string(name) do
      {:ok, pid} ->
        {:ok, pid}

      :error ->
        # Try as module/registered name
        case Code.string_to_quoted(name) do
          {:ok, {:__aliases__, _, parts}} ->
            module = Module.concat(parts)

            case Process.whereis(module) do
              nil -> {:error, "No process registered as #{name}"}
              pid -> {:ok, pid}
            end

          {:ok, atom} when is_atom(atom) ->
            case Process.whereis(atom) do
              nil -> {:error, "No process registered as #{name}"}
              pid -> {:ok, pid}
            end

          _ ->
            # Try as a plain atom
            atom = String.to_existing_atom(name)

            case Process.whereis(atom) do
              nil -> {:error, "No process registered as #{name}"}
              pid -> {:ok, pid}
            end
        end
    end
  rescue
    ArgumentError -> {:error, "Unknown process: #{name}"}
  end

  defp parse_pid_string(str) do
    case String.split(str, ".") do
      [a, b, c] ->
        case {Integer.parse(a), Integer.parse(b), Integer.parse(c)} do
          {{a, ""}, {b, ""}, {c, ""}} ->
            {:ok, :c.pid(a, b, c)}

          _ ->
            :error
        end

      _ ->
        :error
    end
  end

  defp format_pid(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, []} -> inspect(pid)
      {:registered_name, name} -> inspect(name)
      nil -> inspect(pid)
    end
  end

  defp format_pid(port) when is_port(port), do: inspect(port)
  defp format_pid(other), do: inspect(other)

  defp format_mfa({m, f, a}), do: "#{inspect(m)}.#{f}/#{a}"
  defp format_mfa(nil), do: "unknown"
  defp format_mfa(other), do: inspect(other)

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp format_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}K"
  defp format_number(n), do: "#{n}"

  defp indent(depth), do: String.duplicate("  ", depth)
end
