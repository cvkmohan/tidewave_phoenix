defmodule Tidewave.MCP.Tools.Ast do
  @moduledoc false

  def tools do
    if Code.ensure_loaded?(ExAST) do
      [
        %{
          name: "ast_search",
          description: """
          Searches for Elixir code patterns using AST (Abstract Syntax Tree) matching.

          Unlike grep/regex, this understands code structure. Variables in the pattern
          capture matched nodes, `_` is a wildcard, and structs match partially.

          Examples:
          - "Repo.all(query) |> Enum.filter(_)" — find N+1 patterns
          - "Enum.map(x, &(&1))" — find identity maps
          - "%User{name: name}" — find User struct usage (partial match)
          - "case _ do\\n  {:ok, result} -> _\\nend" — find case patterns
          - Function definitions with specific patterns
          """,
          inputSchema: %{
            type: "object",
            required: ["pattern"],
            properties: %{
              pattern: %{
                type: "string",
                description:
                  "Elixir code pattern to search for (variables capture, _ is wildcard)"
              },
              path: %{
                type: "string",
                description: "File or directory to search in (default: \"lib/\")"
              }
            }
          },
          callback: &ast_search/1
        },
        %{
          name: "ast_replace",
          description: """
          Replaces Elixir code patterns using AST matching and substitution.

          Pattern variables captured in the search pattern can be used in the replacement.
          This is safer than regex replacement because it understands code structure.

          Examples:
          - Pattern: "Enum.map(x, &(&1))", Replacement: "x" — remove identity maps
          - Pattern: "IO.inspect(expr)", Replacement: "expr" — remove debug statements

          IMPORTANT: Always use ast_search first to preview matches before replacing.
          """,
          inputSchema: %{
            type: "object",
            required: ["pattern", "replacement"],
            properties: %{
              pattern: %{
                type: "string",
                description: "Elixir code pattern to find (variables capture matched nodes)"
              },
              replacement: %{
                type: "string",
                description: "Replacement pattern (use same variable names from search pattern)"
              },
              path: %{
                type: "string",
                description: "File or directory to apply replacements in (default: \"lib/\")"
              },
              dry_run: %{
                type: "boolean",
                description: "Preview changes without writing files (default: true)"
              }
            }
          },
          callback: &ast_replace/1
        }
      ]
    else
      []
    end
  end

  # ============================================================================
  # ast_search
  # ============================================================================

  def ast_search(%{"pattern" => pattern} = args) do
    path = Map.get(args, "path", "lib/")

    try do
      results = ExAST.search(path, pattern)

      if Enum.empty?(results) do
        {:ok, "No matches found for pattern: `#{pattern}`"}
      else
        formatted =
          results
          |> Enum.map_join("\n\n", fn match ->
            location = extract_location(match)
            code = extract_code(match)
            "### #{location}\n\n```elixir\n#{code}\n```"
          end)

        {:ok,
         "# AST Search Results\n\nPattern: `#{pattern}`\nMatches: #{length(results)}\n\n#{formatted}"}
      end
    rescue
      e ->
        {:error, "AST search failed: #{Exception.message(e)}"}
    end
  end

  def ast_search(_), do: {:error, :invalid_arguments}

  # ============================================================================
  # ast_replace
  # ============================================================================

  def ast_replace(%{"pattern" => pattern, "replacement" => replacement} = args) do
    path = Map.get(args, "path", "lib/")
    dry_run = Map.get(args, "dry_run", true)

    try do
      if dry_run do
        results = ExAST.search(path, pattern)

        if Enum.empty?(results) do
          {:ok, "No matches found for pattern: `#{pattern}`. Nothing to replace."}
        else
          formatted =
            results
            |> Enum.map_join("\n", fn match ->
              location = extract_location(match)
              code = extract_code(match)
              "* `#{location}`: `#{String.slice(code, 0, 80)}`"
            end)

          {:ok,
           """
           # AST Replace Preview (dry run)

           Pattern: `#{pattern}`
           Replacement: `#{replacement}`
           Matches: #{length(results)}

           #{formatted}

           Set dry_run to false to apply these changes.
           """}
        end
      else
        result = ExAST.replace(path, pattern, replacement)

        case result do
          changes when is_list(changes) and changes != [] ->
            replacement_count = count_replacements(changes)

            summary =
              changes
              |> Enum.map_join("\n", fn change -> "* #{describe_change(change)}" end)

            {:ok,
             "# AST Replace Results\n\nApplied #{replacement_count} replacement(s) across #{length(changes)} file(s):\n\n#{summary}\n\nRun `mix format` to fix formatting."}

          [] ->
            {:ok, "No replacements made."}

          other ->
            {:ok, "Replacement complete: #{inspect(other)}"}
        end
      end
    rescue
      e ->
        {:error, "AST replace failed: #{Exception.message(e)}"}
    end
  end

  def ast_replace(_), do: {:error, :invalid_arguments}

  # ============================================================================
  # Helpers
  # ============================================================================

  defp extract_location(match) do
    cond do
      is_map(match) and Map.has_key?(match, :file) and Map.has_key?(match, :line) ->
        "#{match.file}:#{match.line}"

      is_map(match) and Map.has_key?(match, :file) ->
        match.file

      is_tuple(match) and tuple_size(match) >= 2 ->
        "#{elem(match, 0)}:#{elem(match, 1)}"

      true ->
        inspect(match)
    end
  end

  defp extract_code(match) do
    cond do
      is_map(match) and Map.has_key?(match, :source) ->
        match.source

      is_map(match) and Map.has_key?(match, :node) ->
        Macro.to_string(match.node)

      is_tuple(match) and tuple_size(match) >= 3 ->
        elem(match, 2) |> to_string()

      true ->
        inspect(match)
    end
  end

  defp describe_change(change) do
    cond do
      is_tuple(change) and tuple_size(change) == 2 ->
        {file, count} = change
        "#{file}: #{count} replacement(s)"

      is_map(change) and Map.has_key?(change, :file) ->
        "#{change.file}: #{Map.get(change, :count, 1)} replacement(s)"

      is_binary(change) ->
        change

      true ->
        inspect(change)
    end
  end

  defp count_replacements(changes) do
    Enum.reduce(changes, 0, fn
      {_file, count}, acc when is_integer(count) ->
        acc + count

      %{count: count}, acc when is_integer(count) ->
        acc + count

      _change, acc ->
        acc + 1
    end)
  end
end
