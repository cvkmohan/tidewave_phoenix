defmodule Tidewave.MCP.Tools.ApiSpec do
  @moduledoc false

  def tools do
    if Code.ensure_loaded?(PhoenixSpec) do
      [
        %{
          name: "generate_api_spec",
          description: """
          Generates an OpenAPI 3.1 specification from the Phoenix application's existing code.

          Automatically infers the API schema from:
          - Ecto schemas (field types, associations)
          - JSON views (exposed fields, nesting)
          - Router definitions (routes, HTTP verbs, path parameters)

          No annotations or DSL needed — it introspects your codebase directly.
          """,
          inputSchema: %{
            type: "object",
            properties: %{
              format: %{
                type: "string",
                enum: ["json", "yaml", "typescript"],
                description: "Output format (default: \"json\")"
              }
            }
          },
          callback: &generate_api_spec/1
        }
      ]
    else
      []
    end
  end

  def generate_api_spec(args) do
    format = Map.get(args, "format", "json")

    try do
      argv =
        case format do
          "typescript" -> ["--format", "ts"]
          "yaml" -> ["--format", "yaml"]
          _ -> []
        end

      # Run the mix task programmatically
      # PhoenixSpec typically provides a mix task, but we'll try the programmatic API first
      # PhoenixSpec only exposes a mix task
      result = Mix.Task.rerun("phoenix_spec.gen", argv)

      case result do
        {:ok, spec} when is_binary(spec) ->
          {:ok, "# Generated OpenAPI Spec\n\n```#{format}\n#{spec}\n```"}

        {:ok, spec} when is_map(spec) ->
          {:ok, "# Generated OpenAPI Spec\n\n```json\n#{Jason.encode!(spec, pretty: true)}\n```"}

        spec when is_binary(spec) ->
          {:ok, "# Generated OpenAPI Spec\n\n```#{format}\n#{spec}\n```"}

        spec when is_map(spec) ->
          {:ok, "# Generated OpenAPI Spec\n\n```json\n#{Jason.encode!(spec, pretty: true)}\n```"}

        :ok ->
          # Mix task wrote to file, try to read it
          output_path =
            case format do
              "typescript" -> "api.d.ts"
              "yaml" -> "priv/static/openapi.yaml"
              _ -> "priv/static/openapi.json"
            end

          if File.exists?(output_path) do
            content = File.read!(output_path)
            ext = if format == "typescript", do: "typescript", else: format

            {:ok,
             "# Generated OpenAPI Spec\n\nWritten to `#{output_path}`\n\n```#{ext}\n#{content}\n```"}
          else
            {:ok, "OpenAPI spec generated successfully. Check priv/static/ for output."}
          end

        other ->
          {:ok, "Generation result: #{inspect(other)}"}
      end
    rescue
      e ->
        {:error, "API spec generation failed: #{Exception.message(e)}"}
    end
  end
end
