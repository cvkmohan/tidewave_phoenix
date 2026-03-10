defmodule Tidewave.MCP.Tools.Xref do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_deps_tree",
        description: """
        Returns the module dependency graph for the project.

        Shows which modules call which other modules, helping understand coupling
        and architecture. Can focus on a specific module to see its callers and callees.

        Uses Mix.Xref for accurate cross-reference data from compilation.
        """,
        inputSchema: %{
          type: "object",
          properties: %{
            module: %{
              type: "string",
              description:
                "Optional module to focus on (e.g., \"MyApp.Accounts\"). Shows both callers and callees. If omitted, shows a summary of all module dependencies."
            },
            mode: %{
              type: "string",
              enum: ["callers", "callees", "both"],
              description: "Show callers, callees, or both (default: \"both\")"
            }
          }
        },
        callback: &get_deps_tree/1
      }
    ]
  end

  def get_deps_tree(args) do
    module_filter = Map.get(args, "module")
    mode = Map.get(args, "mode", "both")

    if module_filter do
      case parse_module(module_filter) do
        {:ok, module} -> get_module_deps(module, module_filter, mode)
        {:error, reason} -> {:error, reason}
      end
    else
      get_project_deps_summary()
    end
  end

  # Fallback removed — get_deps_tree/1 already handles all args via Map.get defaults

  defp get_module_deps(module, module_name, mode) do
    # Get all calls from xref
    calls = get_xref_calls()

    sections = []

    sections =
      if mode in ["callees", "both"] do
        callees =
          calls
          |> Enum.filter(fn {caller, _callee} -> caller == module end)
          |> Enum.map(fn {_caller, callee} -> callee end)
          |> Enum.uniq()
          |> Enum.sort()

        if Enum.empty?(callees) do
          sections ++ ["## Callees (modules called by #{module_name})\n\nNone found."]
        else
          list = Enum.map(callees, &"* `#{inspect(&1)}`") |> Enum.join("\n")

          sections ++
            ["## Callees (#{length(callees)} modules called by #{module_name})\n\n#{list}"]
        end
      else
        sections
      end

    sections =
      if mode in ["callers", "both"] do
        callers =
          calls
          |> Enum.filter(fn {_caller, callee} -> callee == module end)
          |> Enum.map(fn {caller, _callee} -> caller end)
          |> Enum.uniq()
          |> Enum.sort()

        if Enum.empty?(callers) do
          sections ++ ["## Callers (modules that call #{module_name})\n\nNone found."]
        else
          list = Enum.map(callers, &"* `#{inspect(&1)}`") |> Enum.join("\n")

          sections ++
            ["## Callers (#{length(callers)} modules that call #{module_name})\n\n#{list}"]
        end
      else
        sections
      end

    {:ok, "# Dependencies: #{module_name}\n\n" <> Enum.join(sections, "\n\n")}
  end

  defp get_project_deps_summary do
    calls = get_xref_calls()

    if Enum.empty?(calls) do
      {:ok, "No cross-reference data available. The project may need to be compiled first."}
    else
      # Build adjacency counts
      caller_counts =
        calls
        |> Enum.map(fn {caller, _} -> caller end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> count end, :desc)
        |> Enum.take(30)

      callee_counts =
        calls
        |> Enum.map(fn {_, callee} -> callee end)
        |> Enum.frequencies()
        |> Enum.sort_by(fn {_, count} -> count end, :desc)
        |> Enum.take(30)

      unique_modules =
        calls
        |> Enum.flat_map(fn {a, b} -> [a, b] end)
        |> Enum.uniq()
        |> length()

      caller_rows =
        caller_counts
        |> Enum.map(fn {mod, count} -> "| `#{inspect(mod)}` | #{count} |" end)
        |> Enum.join("\n")

      callee_rows =
        callee_counts
        |> Enum.map(fn {mod, count} -> "| `#{inspect(mod)}` | #{count} |" end)
        |> Enum.join("\n")

      {:ok,
       """
       # Project Module Dependencies

       Total modules: #{unique_modules}, Total edges: #{length(calls)}

       ## Top Modules by Outgoing Dependencies (most coupled)

       | Module | Calls To |
       |--------|----------|
       #{caller_rows}

       ## Top Modules by Incoming Dependencies (most depended on)

       | Module | Called By |
       |--------|-----------|
       #{callee_rows}

       Use `get_deps_tree` with a specific module name for detailed caller/callee analysis.
       """}
    end
  end

  defp get_xref_calls do
    # Use Mix.Xref if available (it should be in dev)
    try do
      # Mix.Xref may not be available at compile time but is at runtime in dev
      calls = apply(Mix.Xref, :calls, [])

      calls
      |> Enum.map(fn
        %{caller_module: caller, callee_module: callee} -> {caller, callee}
        {caller, callee} when is_atom(caller) and is_atom(callee) -> {caller, callee}
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.uniq()
    rescue
      _ -> fallback_xref()
    catch
      _, _ -> fallback_xref()
    end
  end

  defp fallback_xref do
    # Fallback: use the loaded modules and their attributes
    for {mod, _} <- :code.all_loaded(),
        app_module?(mod),
        {:ok, calls} <- [try_get_calls(mod)],
        callee <- calls,
        callee != mod,
        do: {mod, callee}
  end

  defp try_get_calls(module) do
    # Get behaviour implementations and other compile-time references
    attrs = module.module_info(:attributes)

    behaviours = Keyword.get(attrs, :behaviour, [])

    impls =
      Keyword.get(attrs, :impl, [])
      |> Enum.map(fn opts -> opts[:for] end)
      |> Enum.reject(&is_nil/1)

    {:ok, behaviours ++ impls}
  rescue
    _ -> {:ok, []}
  end

  defp app_module?(module) do
    source = module.module_info(:compile)[:source]

    if source do
      source
      |> List.to_string()
      |> String.contains?("/lib/")
    else
      false
    end
  rescue
    _ -> false
  end

  defp parse_module(module_name) when is_binary(module_name) do
    case Code.string_to_quoted(module_name) do
      {:ok, {:__aliases__, _, parts}} when is_list(parts) ->
        {:ok, Module.concat(parts)}

      {:ok, atom} when is_atom(atom) ->
        {:ok, atom}

      _ ->
        {:error, "Invalid module name: #{module_name}"}
    end
  end
end
