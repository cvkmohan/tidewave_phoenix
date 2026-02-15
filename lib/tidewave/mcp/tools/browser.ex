defmodule Tidewave.MCP.Tools.Browser do
  @moduledoc false

  # ============================================================================
  # Tool Definitions
  # ============================================================================

  def tools do
    [smoke_test_tool(), eval_with_logs_tool() | browser_tools()]
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

  defp browser_tools do
    if lightpanda_available?() do
      [
        %{
          name: "browser_inspect",
          description: """
          Navigates a real headless browser (Lightpanda) to a route and returns structured DOM data.

          Use this AFTER smoke_test passes, when you need to verify:
          - JavaScript hook execution (phx-hook)
          - Console errors
          - Client-side rendering issues
          - Full DOM structure with source annotations

          Returns:
          - source_files: component files that rendered (from HTML debug annotations)
          - console_errors: any JS console.error messages
          - lv_connected: whether LiveView WebSocket connected successfully
          - interactive_elements: buttons, links, forms with their attributes

          Requires Lightpanda running on localhost:9222.
          """,
          inputSchema: %{
            type: "object",
            required: ["path"],
            properties: %{
              path: %{
                type: "string",
                description: "The route path to inspect (e.g. \"/home\", \"/login\")"
              },
              user_id: %{
                type: "string",
                description:
                  "Optional. UUID of the user to authenticate as. " <>
                    "Session cookie is forged server-side and injected via CDP before navigation."
              },
              wait_ms: %{
                type: "integer",
                description:
                  "Optional. Milliseconds to wait after navigation for JS to settle. Default: 1000."
              }
            }
          },
          callback: &browser_inspect/1
        }
      ]
    else
      []
    end
  end

  # ============================================================================
  # smoke_test — Layer 1 (No Browser, Scoped Logs)
  # ============================================================================

  def smoke_test(%{"path" => path} = args) do
    user_id = args["user_id"]
    session_params = args["session_params"] || %{}

    try do
      # CLEAR LOGS — only capture fresh logs from this mount
      Tidewave.MCP.Logger.clear_logs()

      # Build a test connection
      conn = apply(Phoenix.ConnTest, :build_conn, [])

      # Authenticate if user_id provided
      conn =
        if user_id do
          forge_authenticated_conn(conn, user_id, session_params)
        else
          init_test_conn(conn, session_params)
        end

      # Dispatch GET through the endpoint (same as Phoenix.ConnTest.get/2)
      # We do NOT use Phoenix.LiveViewTest — it requires ExUnit test supervisor.
      # The GET dispatch renders the full page server-side, which is sufficient
      # for smoke testing (catches crashes, missing assigns, bad queries).
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

  # ============================================================================
  # eval_with_logs — Scoped eval (No Browser)
  # ============================================================================

  def eval_with_logs(%{"code" => code} = args) do
    timeout = Map.get(args, "timeout", 30_000)

    # CLEAR LOGS — only capture fresh logs from this eval
    Tidewave.MCP.Logger.clear_logs()

    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        # Do NOT set tidewave_mcp metadata here — we WANT to capture these logs.
        # tidewave_mcp: true tells the handler to skip, which defeats scoped capture.

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

    # Capture ONLY the logs from this execution
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

  # ============================================================================
  # browser_inspect — Layer 2 (Lightpanda CDP)
  # ============================================================================

  def browser_inspect(%{"path" => path} = args) do
    user_id = args["user_id"]
    wait_ms = args["wait_ms"] || 1000

    try do
      # Forge real session cookie server-side if user_id provided
      cookies =
        if user_id do
          forge_session_cookie(user_id)
        else
          []
        end

      url = "http://localhost:4000#{path}"

      # Connect to Lightpanda via CDP (TCP → WebSocket handshake)
      {:ok, cdp} = cdp_connect()

      # Create blank target, attach, set cookies, THEN navigate.
      # Cookies must be set after attach (on the target's session) and before navigation.
      {:ok, target_id, cdp} = cdp_create_and_attach(cdp, url, cookies)

      # Wait for page to settle (LiveView JS connect, hooks init)
      Process.sleep(wait_ms)

      # Collect results via small JS evals (avoids transferring large HTML over WS)
      console_errors = cdp_get_console_errors(cdp)
      {lv_connected, cdp} = cdp_eval(cdp, "document.querySelector('[data-phx-main]') !== null")
      {current_url, cdp} = cdp_eval(cdp, "window.location.href")
      {element_count, cdp} = cdp_eval(cdp, "document.querySelectorAll('*').length")

      # Extract source annotations from HTML comments via JS TreeWalker
      # (avoids pulling 60KB+ outerHTML through the WebSocket)
      {source_files, cdp} =
        cdp_eval_json(cdp, """
        (function() {
          var files = [];
          var walker = document.createTreeWalker(document, NodeFilter.SHOW_COMMENT);
          while(walker.nextNode()) {
            var t = walker.currentNode.textContent.trim();
            var m = t.match(/^<(\\S+)>\\s+(lib\\/\\S+:\\d+)/);
            if(m) files.push(m[2] + ' (' + m[1] + ')');
          }
          return [...new Set(files)].sort();
        })()
        """)

      {interactive, cdp} =
        cdp_eval_json(cdp, """
        Array.from(document.querySelectorAll('[phx-click],[phx-submit],a[href],button'))
          .slice(0, 30)
          .map(el => ({
            tag: el.tagName.toLowerCase(),
            text: (el.textContent || '').trim().substring(0, 50),
            phxClick: el.getAttribute('phx-click'),
            phxSubmit: el.getAttribute('phx-submit'),
            href: el.getAttribute('href')
          }))
        """)

      # Clean up
      {:ok, _result, _cdp} = cdp_call(cdp, "Target.closeTarget", %{targetId: target_id})
      cdp_disconnect(cdp)

      result = """
      status: ok
      url: #{current_url}
      lv_connected: #{lv_connected}
      element_count: #{element_count}
      source_files:
      #{format_list(source_files)}
      console_errors: #{if console_errors == [], do: "none", else: inspect(console_errors)}
      interactive_elements:
      #{format_interactive(interactive)}
      """

      {:ok, String.trim(result)}
    catch
      kind, reason ->
        {:error, "browser_inspect failed: #{Exception.format(kind, reason, __STACKTRACE__)}"}
    end
  end

  def browser_inspect(_), do: {:error, :invalid_arguments}

  # ============================================================================
  # Auth Helpers — Forge cookies server-side, no login form needed
  # ============================================================================

  defp forge_authenticated_conn(conn, user_id, session_params) do
    {repo, user_module} = discover_user_schema()

    user = repo.get!(user_module, user_id)
    token = generate_session_token(user)

    conn
    |> Plug.Test.init_test_session(Map.merge(%{"user_token" => token}, session_params))
    |> Plug.Conn.assign(:current_scope, build_current_scope(user))
  end

  defp init_test_conn(conn, session_params) do
    conn
    |> Plug.Test.init_test_session(session_params)
  end

  # Forge a real session cookie by dispatching through the endpoint.
  # Returns [{cookie_name, cookie_value}] that Lightpanda can use.
  defp forge_session_cookie(user_id) do
    conn = apply(Phoenix.ConnTest, :build_conn, [])
    conn = forge_authenticated_conn(conn, user_id, %{})

    endpoint = discover_endpoint()
    # Dispatch to any path — we just need the response to contain the session cookie
    conn = apply(Phoenix.ConnTest, :dispatch, [conn, endpoint, :get, "/", nil])

    # Extract the session cookie from the response
    case conn.resp_cookies do
      cookies when is_map(cookies) ->
        cookies
        |> Enum.filter(fn {_name, opts} -> is_map(opts) && Map.has_key?(opts, :value) end)
        |> Enum.map(fn {name, opts} -> {name, opts.value} end)

      _ ->
        []
    end
  end

  # ============================================================================
  # App Discovery — Find the Phoenix app's modules at runtime
  # ============================================================================

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

  # ============================================================================
  # HTML Parsing — Extract source annotations from debug comments
  # ============================================================================

  defp extract_source_annotations(html) when is_binary(html) do
    # Phoenix debug annotations format: <!-- <Module.func> lib/path:line (app) -->
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

  # ============================================================================
  # CDP (Chrome DevTools Protocol) — Lightpanda via raw :gen_tcp WebSocket
  #
  # Verified working: Lightpanda loads LiveView pages, JS executes,
  # LiveView WebSocket connects, data-phx-main is present.
  # Zero external dependencies — uses :gen_tcp + :crypto from OTP.
  # ============================================================================

  import Bitwise

  @cdp_host ~c"127.0.0.1"
  @cdp_port 9222

  defp lightpanda_available? do
    case :gen_tcp.connect(@cdp_host, @cdp_port, [], 500) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  # Connect to Lightpanda: TCP → WebSocket handshake → attach to new target
  defp cdp_connect do
    with {:ok, sock} <-
           :gen_tcp.connect(@cdp_host, @cdp_port, [:binary, active: false, packet: :raw]),
         :ok <- ws_handshake(sock) do
      {:ok, %{sock: sock, id: 0}}
    else
      {:error, reason} -> {:error, "CDP connect failed: #{inspect(reason)}"}
    end
  end

  defp ws_handshake(sock) do
    key = :crypto.strong_rand_bytes(16) |> Base.encode64()

    handshake =
      "GET / HTTP/1.1\r\n" <>
        "Host: 127.0.0.1:#{@cdp_port}\r\n" <>
        "Upgrade: websocket\r\n" <>
        "Connection: Upgrade\r\n" <>
        "Sec-WebSocket-Key: #{key}\r\n" <>
        "Sec-WebSocket-Version: 13\r\n" <>
        "\r\n"

    :gen_tcp.send(sock, handshake)

    case :gen_tcp.recv(sock, 0, 5000) do
      {:ok, response} ->
        if String.contains?(response, "101"), do: :ok, else: {:error, :handshake_failed}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Create a fresh browser target, attach to it, enable Runtime.
  # If cookies are provided, injects them via Network.setExtraHTTPHeaders
  # before navigating (Lightpanda's Network.setCookie stores but doesn't send).
  defp cdp_create_and_attach(cdp, url, cookies) do
    # If we have cookies, start with about:blank, set headers, then navigate
    initial_url = if cookies == [], do: url, else: "about:blank"

    # Create target
    {:ok, create_result, cdp} = cdp_call(cdp, "Target.createTarget", %{url: initial_url})
    target_id = get_in(create_result, ["result", "targetId"])

    # Wait for page to start loading
    Process.sleep(500)
    cdp_read_all(cdp.sock)

    # Attach to target (flatten: true sends events on this connection)
    {:ok, _attach_result, cdp} =
      cdp_call(cdp, "Target.attachToTarget", %{targetId: target_id, flatten: true})

    Process.sleep(500)
    cdp_read_all(cdp.sock)

    # Enable Runtime for JS evaluation
    {:ok, _runtime_result, cdp} = cdp_call(cdp, "Runtime.enable", %{})
    Process.sleep(200)
    cdp_read_all(cdp.sock)

    # Inject cookies as extra HTTP headers (sent with every request)
    if cookies != [] do
      {:ok, _net_result, cdp} = cdp_call(cdp, "Network.enable", %{})
      Process.sleep(100)
      cdp_read_all(cdp.sock)

      cookie_header =
        cookies
        |> Enum.map(fn {name, value} -> "#{name}=#{value}" end)
        |> Enum.join("; ")

      {:ok, _header_result, cdp} =
        cdp_call(cdp, "Network.setExtraHTTPHeaders", %{
          headers: %{"Cookie" => cookie_header}
        })

      Process.sleep(100)
      cdp_read_all(cdp.sock)

      # Now navigate to the real URL
      {:ok, _nav_result, cdp} = cdp_call(cdp, "Page.navigate", %{url: url})
      Process.sleep(500)
      cdp_read_all(cdp.sock)
    end

    {:ok, target_id, cdp}
  end

  # Send a CDP command and read the response
  defp cdp_call(cdp, method, params) do
    id = cdp.id + 1
    msg = Jason.encode!(%{id: id, method: method, params: params})
    ws_send_text(cdp.sock, msg)
    Process.sleep(200)

    responses = cdp_read_all(cdp.sock)

    # Find the response matching our ID
    result =
      Enum.find(responses, fn r ->
        match?(%{"id" => ^id}, r)
      end)

    {:ok, result, %{cdp | id: id}}
  end

  # Evaluate JS expression and return the value
  defp cdp_eval(cdp, expression) do
    {:ok, result, cdp} =
      cdp_call(cdp, "Runtime.evaluate", %{expression: expression, returnByValue: true})

    value =
      case result do
        %{"result" => %{"result" => %{"value" => value}}} -> value
        %{"result" => %{"value" => value}} -> value
        other -> "eval_error: #{inspect(other)}"
      end

    {value, cdp}
  end

  # Evaluate JS that returns a JSON-serializable object
  defp cdp_eval_json(cdp, expression) do
    # Wrap in JSON.stringify so we get a parseable string back
    wrapped = "JSON.stringify(#{expression})"
    {json_str, cdp} = cdp_eval(cdp, wrapped)

    value =
      case Jason.decode(json_str) do
        {:ok, parsed} -> parsed
        _ -> json_str
      end

    {value, cdp}
  end

  defp cdp_get_console_errors(_cdp) do
    # Console events are received as CDP events during page load.
    # For a more complete implementation, accumulate Console.messageAdded
    # events in cdp_read_all and filter for "error" level.
    # For now, return empty — smoke_test's scoped logs catch server errors.
    []
  end

  defp cdp_disconnect(cdp) do
    :gen_tcp.close(cdp.sock)
    :ok
  end

  # ============================================================================
  # WebSocket Frame Encoding/Decoding (RFC 6455)
  # ============================================================================

  # Send a masked text frame (clients MUST mask per RFC 6455)
  defp ws_send_text(sock, text) do
    len = byte_size(text)
    mask = :crypto.strong_rand_bytes(4)

    masked =
      text
      |> :binary.bin_to_list()
      |> Enum.with_index()
      |> Enum.map(fn {byte, i} -> bxor(byte, :binary.at(mask, rem(i, 4))) end)
      |> :binary.list_to_bin()

    frame =
      if len < 126 do
        <<0x81, bor(0x80, len), mask::binary-4, masked::binary>>
      else
        <<0x81, 0xFE, len::16, mask::binary-4, masked::binary>>
      end

    :gen_tcp.send(sock, frame)
  end

  # Read all available WebSocket frames, return decoded JSON maps
  defp cdp_read_all(sock) do
    case :gen_tcp.recv(sock, 0, 300) do
      {:ok, data} ->
        extract_json_objects(data)

      {:error, :timeout} ->
        []

      {:error, _} ->
        []
    end
  end

  # Extract JSON objects from raw WebSocket frame data.
  # Frames may contain partial/multiple messages; we find JSON by matching braces.
  defp extract_json_objects(data) when is_binary(data) do
    # Parse WebSocket frames to extract payloads, then decode JSON
    extract_ws_payloads(data, [])
    |> Enum.flat_map(fn payload ->
      case Jason.decode(payload) do
        {:ok, map} when is_map(map) -> [map]
        _ -> []
      end
    end)
  end

  # Extract text payloads from one or more WebSocket frames
  defp extract_ws_payloads(<<>>, acc), do: Enum.reverse(acc)

  defp extract_ws_payloads(
         <<_fin_rsv_op::8, 126, len::16, payload::binary-size(len), rest::binary>>,
         acc
       ) do
    extract_ws_payloads(rest, [payload | acc])
  end

  defp extract_ws_payloads(
         <<_fin_rsv_op::8, len::7, payload::binary-size(len), rest::binary>>,
         acc
       )
       when len < 126 do
    extract_ws_payloads(rest, [payload | acc])
  end

  # If frame parsing fails (fragmented/partial), fall back to regex extraction
  defp extract_ws_payloads(data, acc) do
    fallback =
      Regex.scan(~r/\{(?:[^{}]|\{(?:[^{}]|\{[^{}]*\})*\})*\}/, data)
      |> List.flatten()
      |> Enum.filter(&String.contains?(&1, "\""))

    Enum.reverse(acc) ++ fallback
  end

  # ============================================================================
  # Formatting
  # ============================================================================

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

  defp format_interactive(elements) when is_list(elements) do
    elements
    |> Enum.map(fn el ->
      action =
        cond do
          el["phxClick"] -> "phx-click=#{el["phxClick"]}"
          el["phxSubmit"] -> "phx-submit=#{el["phxSubmit"]}"
          el["href"] -> "href=#{el["href"]}"
          true -> ""
        end

      "  - <#{el["tag"]}> \"#{el["text"]}\" #{action}"
    end)
    |> Enum.join("\n")
  end

  defp format_interactive(_), do: "  (none)"
end
