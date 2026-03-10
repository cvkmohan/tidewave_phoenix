defmodule Tidewave.MCP.Tools.Types do
  @moduledoc false

  def tools do
    [
      %{
        name: "get_type_specs",
        description: """
        Returns type specifications (@spec, @type, @callback) for a module or specific function.

        Uses BEAM bytecode introspection to extract typespecs. Works for any loaded module
        including your application code, dependencies, and standard library.

        Useful for understanding function signatures, return types, and callback requirements
        before writing code that uses a module.
        """,
        inputSchema: %{
          type: "object",
          required: ["module"],
          properties: %{
            module: %{
              type: "string",
              description:
                "Module name (e.g., \"GenServer\", \"MyApp.Accounts\", \"Phoenix.LiveView\")"
            },
            function: %{
              type: "string",
              description: "Optional function name to filter specs for (e.g., \"handle_call\")"
            }
          }
        },
        callback: &get_type_specs/1
      }
    ]
  end

  def get_type_specs(%{"module" => module_name} = args) do
    function_filter = Map.get(args, "function")

    case parse_module(module_name) do
      {:ok, module} ->
        case Code.ensure_loaded(module) do
          {:module, _} ->
            sections = []

            # Types
            types = fetch_types(module)
            sections = if types != "", do: sections ++ [types], else: sections

            # Specs
            specs = fetch_specs(module, function_filter)
            sections = if specs != "", do: sections ++ [specs], else: sections

            # Callbacks
            callbacks = fetch_callbacks(module, function_filter)
            sections = if callbacks != "", do: sections ++ [callbacks], else: sections

            if Enum.empty?(sections) do
              filter_msg =
                if function_filter, do: " for function '#{function_filter}'", else: ""

              {:ok, "No type specifications found in #{module_name}#{filter_msg}."}
            else
              {:ok, "# Type Specs: #{module_name}\n\n" <> Enum.join(sections, "\n\n")}
            end

          {:error, reason} ->
            {:error, "Could not load module #{module_name}: #{reason}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_type_specs(_), do: {:error, :invalid_arguments}

  defp fetch_types(module) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} when types != [] ->
        formatted =
          types
          |> Enum.sort_by(fn {_kind, {name, _, _}} -> name end)
          |> Enum.map(fn {kind, type_ast} ->
            spec_str = Code.Typespec.type_to_quoted(type_ast) |> Macro.to_string()
            prefix = if kind == :opaque, do: "@opaque", else: "@type"
            "#{prefix} #{spec_str}"
          end)
          |> Enum.join("\n")

        "## Types\n\n```elixir\n#{formatted}\n```"

      _ ->
        ""
    end
  end

  defp fetch_specs(module, function_filter) do
    case Code.Typespec.fetch_specs(module) do
      {:ok, specs} when specs != [] ->
        specs =
          if function_filter do
            filter_atom = String.to_atom(function_filter)
            Enum.filter(specs, fn {{name, _arity}, _} -> name == filter_atom end)
          else
            specs
          end

        if Enum.empty?(specs) do
          ""
        else
          formatted =
            specs
            |> Enum.sort_by(fn {{name, arity}, _} -> {name, arity} end)
            |> Enum.flat_map(fn {{name, _arity}, spec_asts} ->
              Enum.map(spec_asts, fn spec_ast ->
                spec_str =
                  Code.Typespec.spec_to_quoted(name, spec_ast) |> Macro.to_string()

                "@spec #{spec_str}"
              end)
            end)
            |> Enum.join("\n")

          "## Specs\n\n```elixir\n#{formatted}\n```"
        end

      _ ->
        ""
    end
  end

  defp fetch_callbacks(module, function_filter) do
    case Code.Typespec.fetch_callbacks(module) do
      {:ok, callbacks} when callbacks != [] ->
        callbacks =
          if function_filter do
            filter_atom = String.to_atom(function_filter)
            Enum.filter(callbacks, fn {{name, _arity}, _} -> name == filter_atom end)
          else
            callbacks
          end

        if Enum.empty?(callbacks) do
          ""
        else
          formatted =
            callbacks
            |> Enum.sort_by(fn {{name, arity}, _} -> {name, arity} end)
            |> Enum.flat_map(fn {{name, _arity}, spec_asts} ->
              Enum.map(spec_asts, fn spec_ast ->
                spec_str =
                  Code.Typespec.spec_to_quoted(name, spec_ast) |> Macro.to_string()

                "@callback #{spec_str}"
              end)
            end)
            |> Enum.join("\n")

          "## Callbacks\n\n```elixir\n#{formatted}\n```"
        end

      _ ->
        ""
    end
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
