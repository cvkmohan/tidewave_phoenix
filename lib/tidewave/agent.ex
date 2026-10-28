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

  def docs(reference) do
    Tools.Source.get_docs(%{"reference" => reference_to_string(reference)})
  end

  def source(reference) do
    Tools.Source.get_source_location(%{"reference" => reference_to_string(reference)})
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
    with true <- function_exported?(endpoint, :config, 1),
         router when not is_nil(router) <- endpoint.config(:router),
         true <- Code.ensure_loaded?(router),
         true <- function_exported?(router, :__routes__, 0) do
      Enum.map(router.__routes__(), &route_info(endpoint, router, &1))
    else
      _ -> []
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
