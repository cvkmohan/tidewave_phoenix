defmodule Tidewave.MCP.Tools.JsHooks do
  @moduledoc false

  def tools do
    if Code.ensure_loaded?(QuickJSEx) do
      [
        %{
          name: "validate_js_hooks",
          description: """
          Validates Phoenix LiveView JavaScript hooks without a browser.

          Loads the app's JS bundle (or a specific JS file) into an embedded QuickJS engine
          with browser stubs and checks:
          - Bundle parses without syntax errors
          - All hooks referenced by phx-hook in templates are defined
          - Hook objects have the expected callbacks (mounted, updated, destroyed, etc.)
          - No JS errors when loading the bundle

          Use as a quality gate after modifying JS hooks. Runs inside the BEAM — no browser,
          no Lightpanda, no Node.js needed.

          Verification chain: smoke_test (server) → validate_js_hooks (JS) → browser_inspect (full browser)
          """,
          inputSchema: %{
            type: "object",
            properties: %{
              js_path: %{
                type: "string",
                description:
                  "Path to the JS file to validate (default: auto-detects app.js from assets/js/app.js)"
              },
              hook_names: %{
                type: "array",
                items: %{type: "string"},
                description:
                  "Optional list of hook names to verify exist (e.g. [\"MyHook\", \"Chart\"]). " <>
                    "If not provided, scans HEEx templates for phx-hook references."
              }
            }
          },
          callback: &validate_js_hooks/1
        },
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

  # ============================================================================
  # validate_js_hooks
  # ============================================================================

  def validate_js_hooks(args) do
    js_path = Map.get(args, "js_path") || find_app_js()
    requested_hooks = Map.get(args, "hook_names")

    case js_path do
      nil ->
        {:error, "Could not find app.js. Provide js_path parameter."}

      path ->
        case File.read(path) do
          {:ok, js_source} ->
            do_validate_hooks(path, js_source, requested_hooks)

          {:error, reason} ->
            {:error, "Could not read #{path}: #{reason}"}
        end
    end
  end

  # validate_js_hooks always receives a map from MCP dispatch

  defp do_validate_hooks(path, js_source, requested_hooks) do
    {:ok, rt} = QuickJSEx.start(browser_stubs: true)

    try do
      issues = []

      # Step 1: Check if the JS bundle parses
      {parse_ok, parse_issues} = check_bundle_parse(rt, js_source, path)
      issues = issues ++ parse_issues

      if parse_ok do
        # Step 2: Find hooks defined in JS
        {js_hooks, hook_issues} = extract_js_hooks(rt)
        issues = issues ++ hook_issues

        # Step 3: Find hooks referenced in templates
        template_hooks =
          if requested_hooks do
            requested_hooks
          else
            scan_template_hooks()
          end

        # Step 4: Cross-reference
        {xref_issues, xref_info} = cross_reference_hooks(js_hooks, template_hooks)
        issues = issues ++ xref_issues

        # Step 5: Validate hook callbacks
        callback_issues = validate_hook_callbacks(js_hooks)
        issues = issues ++ callback_issues

        format_validation_result(path, issues, js_hooks, template_hooks, xref_info)
      else
        format_validation_result(path, issues, [], [], %{})
      end
    after
      QuickJSEx.stop(rt)
    end
  end

  defp check_bundle_parse(rt, js_source, path) do
    case QuickJSEx.eval(rt, js_source) do
      {:ok, _} ->
        {true, []}

      {:error, error} ->
        {false, [{:error, "Bundle parse error in #{path}: #{error}"}]}
    end
  end

  defp extract_js_hooks(rt) do
    # Try common patterns for how hooks are exported in Phoenix apps
    hook_extraction_js = """
    (function() {
      // Try common hook export patterns
      var hooks = null;

      // Pattern 1: window.Hooks or global Hooks
      if (typeof Hooks !== 'undefined') hooks = Hooks;
      else if (typeof window !== 'undefined' && window.Hooks) hooks = window.Hooks;

      // Pattern 2: liveSocket.hooks (if LiveSocket was created)
      if (!hooks && typeof liveSocket !== 'undefined' && liveSocket.hooks) {
        hooks = liveSocket.hooks;
      }

      // Pattern 3: Check window.liveSocket
      if (!hooks && typeof window !== 'undefined' && window.liveSocket && window.liveSocket.hooks) {
        hooks = window.liveSocket.hooks;
      }

      if (!hooks) return JSON.stringify({found: false, hooks: []});

      var result = Object.entries(hooks).map(function(entry) {
        var name = entry[0];
        var hook = entry[1];
        var callbacks = Object.keys(hook).filter(function(k) {
          return typeof hook[k] === 'function';
        });
        return {
          name: name,
          callbacks: callbacks,
          hasMounted: typeof hook.mounted === 'function',
          hasUpdated: typeof hook.updated === 'function',
          hasDestroyed: typeof hook.destroyed === 'function',
          hasDisconnected: typeof hook.disconnected === 'function',
          hasReconnected: typeof hook.reconnected === 'function'
        };
      });

      return JSON.stringify({found: true, hooks: result});
    })()
    """

    case QuickJSEx.eval(rt, hook_extraction_js) do
      {:ok, json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, %{"found" => true, "hooks" => hooks}} ->
            {hooks, []}

          {:ok, %{"found" => false}} ->
            {[],
             [
               {:warning,
                "No Hooks object found. Hooks may be defined in a module that isn't loaded at top level."}
             ]}

          _ ->
            {[], [{:warning, "Could not parse hook extraction result."}]}
        end

      {:ok, result} when is_map(result) ->
        hooks = Map.get(result, "hooks", [])
        {hooks, []}

      {:error, err} ->
        {[], [{:warning, "Hook extraction failed: #{err}"}]}
    end
  end

  defp scan_template_hooks do
    # Scan HEEx templates for phx-hook="HookName" references
    patterns = ["lib/**/*.heex", "lib/**/*.html.heex"]

    patterns
    |> Enum.flat_map(fn pattern ->
      Path.wildcard(pattern)
    end)
    |> Enum.flat_map(fn file ->
      case File.read(file) do
        {:ok, content} ->
          Regex.scan(~r/phx-hook="([^"]+)"/, content)
          |> Enum.map(fn [_, hook_name] -> hook_name end)

        _ ->
          []
      end
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp cross_reference_hooks(js_hooks, template_hooks) do
    js_hook_names = Enum.map(js_hooks, & &1["name"]) |> MapSet.new()
    template_hook_set = MapSet.new(template_hooks)

    # Hooks in templates but not in JS
    missing_in_js = MapSet.difference(template_hook_set, js_hook_names) |> MapSet.to_list()

    # Hooks in JS but not in templates (informational, not an error)
    unused_in_templates = MapSet.difference(js_hook_names, template_hook_set) |> MapSet.to_list()

    issues =
      Enum.map(missing_in_js, fn hook ->
        {:error,
         "Hook \"#{hook}\" is referenced in templates (phx-hook=\"#{hook}\") but not defined in JS"}
      end)

    info = %{
      missing_in_js: missing_in_js,
      unused_in_templates: unused_in_templates
    }

    {issues, info}
  end

  defp validate_hook_callbacks(js_hooks) do
    Enum.flat_map(js_hooks, fn hook ->
      name = hook["name"]
      callbacks = hook["callbacks"] || []

      issues = []

      # mounted() is the most important callback — warn if missing
      issues =
        if not hook["hasMounted"] do
          issues ++ [{:warning, "Hook \"#{name}\" has no mounted() callback"}]
        else
          issues
        end

      # Check for common misspellings
      known = ~w(mounted updated destroyed disconnected reconnected beforeUpdate beforeDestroy)
      unknown = Enum.reject(callbacks, &(&1 in known))

      issues =
        if unknown != [] do
          issues ++
            [
              {:warning,
               "Hook \"#{name}\" has unknown callbacks: #{Enum.join(unknown, ", ")}. Typo?"}
            ]
        else
          issues
        end

      issues
    end)
  end

  defp format_validation_result(path, issues, js_hooks, template_hooks, xref_info) do
    errors = Enum.filter(issues, fn {level, _} -> level == :error end)
    warnings = Enum.filter(issues, fn {level, _} -> level == :warning end)

    status =
      cond do
        errors != [] -> "FAIL"
        warnings != [] -> "PASS (with warnings)"
        true -> "PASS"
      end

    sections = ["# JS Hook Validation\n\n**Status:** #{status}\n**Bundle:** #{path}"]

    # Hook summary
    sections =
      if js_hooks != [] do
        hook_list =
          js_hooks
          |> Enum.map(fn h ->
            cbs = (h["callbacks"] || []) |> Enum.join(", ")
            "  - `#{h["name"]}`: #{cbs}"
          end)
          |> Enum.join("\n")

        sections ++ ["\n## Hooks Found in JS (#{length(js_hooks)})\n\n#{hook_list}"]
      else
        sections
      end

    sections =
      if template_hooks != [] do
        refs = Enum.map(template_hooks, &"  - `#{&1}`") |> Enum.join("\n")
        sections ++ ["\n## Hooks Referenced in Templates (#{length(template_hooks)})\n\n#{refs}"]
      else
        sections
      end

    # Missing hooks
    missing = Map.get(xref_info, :missing_in_js, [])

    sections =
      if missing != [] do
        list =
          Enum.map(missing, &"  - **#{&1}** — referenced in template but not defined")
          |> Enum.join("\n")

        sections ++ ["\n## Missing Hooks\n\n#{list}"]
      else
        sections
      end

    # Unused hooks (informational)
    unused = Map.get(xref_info, :unused_in_templates, [])

    sections =
      if unused != [] do
        list = Enum.map(unused, &"  - #{&1}") |> Enum.join("\n")
        sections ++ ["\n## Unused Hooks (defined but not in templates)\n\n#{list}"]
      else
        sections
      end

    # Issues
    sections =
      if errors != [] do
        list = Enum.map(errors, fn {_, msg} -> "  - #{msg}" end) |> Enum.join("\n")
        sections ++ ["\n## Errors\n\n#{list}"]
      else
        sections
      end

    sections =
      if warnings != [] do
        list = Enum.map(warnings, fn {_, msg} -> "  - #{msg}" end) |> Enum.join("\n")
        sections ++ ["\n## Warnings\n\n#{list}"]
      else
        sections
      end

    result = Enum.join(sections, "\n")

    if errors != [] do
      {:ok, result}
    else
      {:ok, result}
    end
  end

  # ============================================================================
  # eval_js
  # ============================================================================

  def eval_js(%{"code" => code} = args) do
    load_app = Map.get(args, "load_app_js", false)

    {:ok, rt} = QuickJSEx.start(browser_stubs: true)

    try do
      # Optionally load app.js first
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

  # ============================================================================
  # Helpers
  # ============================================================================

  defp find_app_js do
    candidates = [
      "assets/js/app.js",
      "assets/app.js",
      "priv/static/assets/app.js"
    ]

    Enum.find(candidates, &File.exists?/1)
  end
end
