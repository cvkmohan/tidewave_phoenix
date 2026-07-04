defmodule Tidewave.Agent do
  @moduledoc false

  alias Tidewave.MCP.Tools

  @default_inspect_opts [charlists: :as_lists, limit: 50, pretty: true]

  def project do
    %{
      root: Tidewave.MCP.root(),
      project_name: Tidewave.MCP.project_name(),
      mix_project: Mix.Project.config()[:app],
      mix_env: Mix.env(),
      elixir: System.version(),
      otp: System.otp_release()
    }
  end

  def clear_logs, do: Tidewave.clear_logs()

  def logs(opts \\ []) do
    args =
      opts
      |> Map.new()
      |> normalize_keys()
      |> Map.put_new("tail", 50)

    Tools.Logs.get_logs(args)
  end

  def sql(query, opts \\ []) when is_binary(query) do
    args =
      opts
      |> Map.new()
      |> normalize_keys()
      |> Map.put("query", query)
      |> Map.put_new("arguments", [])

    Tools.Ecto.execute_sql_query(args, agent_config())
  end

  def ecto_schemas do
    Tools.Ecto.get_ecto_schemas(%{})
  end

  def ash_resources do
    if Code.ensure_loaded?(Ash) do
      Tools.Ash.get_ash_resources(%{})
    else
      {:error, "Ash is not loaded in this project"}
    end
  end

  def docs(reference) do
    Tools.Source.get_docs(%{"reference" => reference_to_string(reference)})
  end

  def source(reference) do
    Tools.Source.get_source_location(%{"reference" => reference_to_string(reference)})
  end

  def module_functions(module) when is_atom(module) do
    module_functions(inspect(module))
  end

  def module_functions(module) when is_binary(module) do
    Tools.Phoenix.get_module_functions(%{"module" => module})
  end

  def component(component) do
    Tools.Phoenix.get_component_info(%{"component" => reference_to_string(component)})
  end

  def smoke_test(path, opts \\ []) when is_binary(path) do
    args =
      opts
      |> Map.new()
      |> normalize_keys()
      |> Map.put("path", path)

    Tools.Browser.smoke_test(args)
  end

  def eval_with_logs(code, opts \\ []) when is_binary(code) do
    args =
      opts
      |> Map.new()
      |> normalize_keys()
      |> Map.put("code", code)

    Tools.Browser.eval_with_logs(args)
  end

  def validate_js_hooks(opts \\ []) do
    if Code.ensure_loaded?(QuickJSEx) do
      opts |> Map.new() |> normalize_keys() |> Tools.JsHooks.validate_js_hooks()
    else
      {:error, "QuickJSEx is not loaded in this project"}
    end
  end

  def routes(endpoint \\ nil) do
    endpoint
    |> resolve_endpoints()
    |> Enum.flat_map(&endpoint_routes/1)
    |> case do
      [] -> {:error, "No Phoenix routes found"}
      routes -> {:ok, routes}
    end
  end

  defp resolve_endpoints(nil) do
    for {app, _, _} <- Application.started_applications(),
        endpoint <- Application.get_env(app, :phoenix_endpoint, []) |> List.wrap(),
        Code.ensure_loaded?(endpoint) do
      endpoint
    end
  end

  defp resolve_endpoints(endpoint) when is_atom(endpoint), do: [endpoint]

  defp endpoint_routes(endpoint) do
    with {:ok, router} <- endpoint_router(endpoint),
         true <- Code.ensure_loaded?(router),
         true <- function_exported?(router, :__routes__, 0) do
      Enum.map(router.__routes__(), &route_info(endpoint, router, &1))
    else
      _ -> []
    end
  end

  defp endpoint_router(endpoint) do
    cond do
      function_exported?(endpoint, :config, 1) ->
        case endpoint.config(:router) do
          nil -> {:error, :router_not_configured}
          router -> {:ok, router}
        end

      true ->
        {:error, :router_not_configured}
    end
  end

  defp route_info(endpoint, router, route) do
    %{
      endpoint: endpoint,
      router: router,
      verb: route.verb,
      path: route.path,
      plug: route.plug,
      plug_opts: route.plug_opts,
      helper: Map.get(route, :helper)
    }
  end

  defp reference_to_string(reference) when is_binary(reference), do: reference
  defp reference_to_string(reference) when is_atom(reference), do: inspect(reference)

  defp reference_to_string({module, function}) when is_atom(module) and is_atom(function) do
    "#{inspect(module)}.#{function}"
  end

  defp reference_to_string({module, function, arity})
       when is_atom(module) and is_atom(function) and is_integer(arity) do
    "#{inspect(module)}.#{function}/#{arity}"
  end

  defp normalize_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp agent_config do
    %{
      inspect_opts: Application.get_env(:tidewave, :inspect_opts, @default_inspect_opts),
      phoenix_endpoint: nil
    }
  end
end
