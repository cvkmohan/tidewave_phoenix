defmodule Tidewave.MCP.Tools.Browser do
  @moduledoc false

  def tools do
    [smoke_test_tool(), eval_with_logs_tool()]
  end

  defp smoke_test_tool do
    %{
      name: "smoke_test",
      description: """
      Mounts a Phoenix LiveView route inside the BEAM and returns structured verification data.
      No browser needed — this runs entirely server-side.

      Use this as the PRIMARY verification tool after writing or modifying LiveView code.
      It catches: crashes, redirects, missing assigns, undefined functions, bad queries.

      Logs are SCOPED — only logs generated during this specific mount are returned.
      No stale log noise from previous operations.

      Returns a structured result with:
      - status: ok | redirect | live_redirect | error
      - source_files: list of component files that rendered (from debug annotations)
      - logs_during_mount: only the log lines produced during this page mount
      - redirect_to: where it redirected (if status is redirect)
      - error: crash details (if status is error)

      IMPORTANT: A redirect to "/login" or any auth path means the page requires
      authentication. Pass a user_id to test as an authenticated user.
      A redirect is NOT a successful verification.
      """,
      inputSchema: %{
        type: "object",
        required: ["path"],
        properties: %{
          path: %{
            type: "string",
            description: "The route path to test (e.g. \"/home\", \"/workbooks/UUID/content\")"
          },
          user_id: %{
            type: "string",
            description:
              "Optional. UUID of the user to authenticate as. " <>
                "Query the database first to get a real user ID. " <>
                "If not provided, tests as an unauthenticated visitor."
          },
          session_params: %{
            type: "object",
            description:
              "Optional. Additional session parameters to set before mounting " <>
                "(e.g. %{\"org_id\" => \"uuid\"} for org-scoped routes)."
          }
        }
      },
      callback: &smoke_test/1
    }
  end

  defp eval_with_logs_tool do
    %{
      name: "eval_with_logs",
      description: """
      Evaluates Elixir code and returns BOTH the result AND only the logs generated during execution.
      Logs are scoped — no stale log noise from previous runs.

      Use this instead of project_eval + get_logs when debugging errors.
      It clears the log buffer before execution, runs the code, then captures only fresh logs.

      Returns:
      - result or error from the evaluation
      - logs: only log lines produced during this specific execution

      Example: eval_with_logs("MyApp.SomeModule.some_function()")
      """,
      inputSchema: %{
        type: "object",
        required: ["code"],
        properties: %{
          code: %{
            type: "string",
            description: "The Elixir code to evaluate"
          },
          timeout: %{
            type: "integer",
            description: "Optional. Max execution time in milliseconds. Default: 30000."
          }
        }
      },
      callback: &eval_with_logs/1
    }
  end

  def smoke_test(%{"path" => path} = args) do
    user_id = args["user_id"]
    session_params = args["session_params"] || %{}

    try do
      Tidewave.MCP.Logger.clear_logs()

      conn = apply(Phoenix.ConnTest, :build_conn, [])

      conn =
        if user_id do
          forge_authenticated_conn(conn, user_id, session_params)
        else
          init_test_conn(conn, session_params)
        end

      endpoint = discover_endpoint()
      conn = apply(Phoenix.ConnTest, :dispatch, [conn, endpoint, :get, path, nil])

      mount_logs = Tidewave.MCP.Logger.get_logs(30)

      case {conn.status, conn.resp_body} do
        {200, html} ->
          source_files = extract_source_annotations(html)

          result = """
          status: ok
          live_module: #{inspect(conn.assigns[:live_module])}
          source_files:
          #{format_list(source_files)}
          html_size: #{byte_size(html)} bytes
          element_count: #{count_elements(html)}
          #{format_scoped_logs(mount_logs)}
          """

          {:ok, String.trim(result)}

        {302, _} ->
          location = Plug.Conn.get_resp_header(conn, "location") |> List.first()
          flash = conn.private[:phoenix_flash] || %{}

          result = """
          status: redirect
          redirect_to: #{location}
          #{if flash != %{}, do: "flash: #{inspect(flash)}", else: ""}
          NOTE: This is NOT a successful render. The page redirected.
          #{format_scoped_logs(mount_logs)}
          """

          {:ok, String.trim(result)}

        {status, _} ->
          result = """
          status: error
          http_status: #{status}
          #{format_scoped_logs(mount_logs)}
          """

          {:ok, String.trim(result)}
      end
    catch
      kind, reason ->
        error_logs = Tidewave.MCP.Logger.get_logs(30)

        {:error,
         "smoke_test crashed: #{Exception.format(kind, reason, __STACKTRACE__)}\n\nlogs_during_mount:\n#{Enum.join(error_logs, "\n")}"}
    end
  end

  def smoke_test(_), do: {:error, :invalid_arguments}

  def eval_with_logs(%{"code" => code} = args) do
    timeout = Map.get(args, "timeout", 30_000)

    Tidewave.MCP.Logger.clear_logs()

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        {success?, result} =
          try do
            {result, _} = Code.eval_string(code, [], eval_env())
            {true, inspect(result, pretty: true, limit: 50)}
          catch
            kind, reason ->
              {false, Exception.format(kind, reason, __STACKTRACE__)}
          end

        send(parent, {:eval_result, success?, result})
      end)

    {success?, result} =
      receive do
        {:eval_result, success?, result} ->
          Process.demonitor(ref, [:flush])
          {success?, result}

        {:DOWN, ^ref, :process, ^pid, reason} ->
          {false, "Process exited: #{Exception.format_exit(reason)}"}
      after
        timeout ->
          Process.demonitor(ref, [:flush])
          Process.exit(pid, :brutal_kill)
          {false, "Evaluation timed out after #{timeout}ms"}
      end

    logs = Tidewave.MCP.Logger.get_logs(30)

    output = """
    #{if success?, do: "result:", else: "error:"}
    #{result}
    #{format_scoped_logs(logs)}
    """

    {:ok, String.trim(output)}
  end

  def eval_with_logs(_), do: {:error, :invalid_arguments}

  defp eval_env do
    import IEx.Helpers, warn: false
    __ENV__
  end

  defp forge_authenticated_conn(conn, user_id, session_params) do
    {repo, user_module} = discover_user_schema()

    user = repo.get!(user_module, user_id)
    token = generate_session_token(user)

    conn
    |> Plug.Test.init_test_session(Map.merge(%{"user_token" => token}, session_params))
    |> Plug.Conn.assign(:current_scope, build_current_scope(user))
  end

  defp init_test_conn(conn, session_params) do
    Plug.Test.init_test_session(conn, session_params)
  end

  defp discover_user_schema do
    repos = discover_repos()
    repo = List.first(repos)

    user_module =
      discover_schema_with_fields([:email, :hashed_password]) ||
        raise "Could not find a User schema with :email and :hashed_password fields"

    {repo, user_module}
  end

  defp discover_repos do
    apps =
      if apps_paths = Mix.Project.apps_paths() do
        Enum.filter(Mix.Project.deps_apps(), &is_map_key(apps_paths, &1))
      else
        [Mix.Project.config()[:app]]
      end

    apps
    |> Enum.flat_map(fn app ->
      Application.load(app)
      Application.get_env(app, :ecto_repos, [])
    end)
    |> Enum.uniq()
  end

  defp discover_schema_with_fields(required_fields) do
    build_path = Mix.Project.build_path()
    app = Mix.Project.config()[:app]

    files = File.ls!(Path.join(build_path, "lib/#{app}/ebin"))

    modules =
      for file <- files, [basename, ""] <- [:binary.split(file, ".beam")] do
        String.to_atom(basename)
      end

    Enum.find(modules, fn mod ->
      Code.ensure_loaded?(mod) &&
        function_exported?(mod, :__schema__, 1) &&
        Enum.all?(required_fields, &(&1 in mod.__schema__(:fields)))
    end)
  end

  defp discover_endpoint do
    app = Mix.Project.config()[:app]
    app_module = app |> Atom.to_string() |> Macro.camelize()
    Module.concat([app_module <> "Web", "Endpoint"])
  end

  defp generate_session_token(user) do
    app = Mix.Project.config()[:app]
    app_module = app |> Atom.to_string() |> Macro.camelize()
    accounts_module = Module.concat([app_module, "Accounts"])

    if Code.ensure_loaded?(accounts_module) &&
         function_exported?(accounts_module, :generate_user_session_token, 1) do
      accounts_module.generate_user_session_token(user)
    else
      raise "Could not find #{accounts_module}.generate_user_session_token/1"
    end
  end

  defp build_current_scope(user) do
    app = Mix.Project.config()[:app]
    app_module = app |> Atom.to_string() |> Macro.camelize()
    scope_module = Module.concat([app_module, "Authorization", "Scope"])

    if Code.ensure_loaded?(scope_module) && function_exported?(scope_module, :for_user, 1) do
      scope_module.for_user(user)
    else
      %{user: user}
    end
  end

  defp extract_source_annotations(html) when is_binary(html) do
    Regex.scan(~r/<!-- <(\S+)> (lib\/\S+:\d+)/, html)
    |> Enum.map(fn [_, mod, loc] -> "#{loc} (#{mod})" end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp extract_source_annotations(_), do: []

  defp count_elements(html) when is_binary(html) do
    Regex.scan(~r/<[a-z][\w-]*/i, html) |> length()
  end

  defp count_elements(_), do: 0

  defp format_list([]), do: "  (none)"

  defp format_list(items) do
    items
    |> Enum.map(&"  - #{&1}")
    |> Enum.join("\n")
  end

  defp format_scoped_logs([]), do: "logs: (clean — no warnings or errors)"

  defp format_scoped_logs(logs) do
    "logs_during_operation:\n" <> Enum.join(logs, "\n")
  end
end
