defmodule Tidewave.MCP.Tools.JsHooks do
  @moduledoc false

  def tools do
    if Code.ensure_loaded?(QuickJSEx) do
      [
        %{
          name: "eval_js",
          description: """
          Evaluates JavaScript code in an embedded QuickJS engine with browser stubs.

          Runs JS inside the BEAM — no Node.js, no browser needed. Useful for:
          - Testing hook logic
          - Validating JS utility functions
          - Checking if a JS snippet parses
          - Running JS-based data transformations

          The runtime has browser stubs (window, document, localStorage, navigator, etc.)
          so most client-side code will parse without errors.
          """,
          inputSchema: %{
            type: "object",
            required: ["code"],
            properties: %{
              code: %{
                type: "string",
                description: "JavaScript code to evaluate"
              },
              load_app_js: %{
                type: "boolean",
                description:
                  "Load the Phoenix app's JS bundle first (default: false). " <>
                    "Useful for testing code that depends on app globals."
              }
            }
          },
          callback: &eval_js/1
        }
      ]
    else
      []
    end
  end

  def eval_js(%{"code" => code} = args) do
    load_app = Map.get(args, "load_app_js", false)

    {:ok, rt} = QuickJSEx.start(browser_stubs: true)

    try do
      if load_app do
        case find_app_js() do
          nil ->
            :skip

          path ->
            case File.read(path) do
              {:ok, js} -> QuickJSEx.eval(rt, js)
              _ -> :skip
            end
        end
      end

      case QuickJSEx.eval(rt, code) do
        {:ok, result} ->
          formatted =
            case result do
              r when is_binary(r) -> r
              r -> inspect(r, pretty: true)
            end

          {:ok, formatted}

        {:error, error} ->
          {:error, "JS error: #{error}"}
      end
    after
      QuickJSEx.stop(rt)
    end
  end

  def eval_js(_), do: {:error, :invalid_arguments}

  defp find_app_js do
    candidates = [
      "assets/js/app.js",
      "assets/app.js",
      "priv/static/assets/app.js"
    ]

    Enum.find(candidates, &File.exists?/1)
  end
end
