defmodule Tidewave.MCP.ToolsProfileTest do
  use ExUnit.Case, async: false

  alias Tidewave.MCP.Server

  setup do
    previous = Application.get_env(:tidewave, :tools_profile)

    on_exit(fn ->
      restore_profile(previous)
      Server.init_tools()
    end)

    :ok
  end

  test "full profile exposes the normal tool list" do
    Application.put_env(:tidewave, :tools_profile, :full)
    Server.init_tools()

    {tools, _dispatch} = Server.tools_and_dispatch()
    tool_names = tool_names(tools)

    assert "project_eval" in tool_names
    assert "smoke_test" in tool_names
    assert "get_logs" in tool_names
    assert "get_component_info" in tool_names
    assert "validate_js_hooks" in tool_names
  end

  test "minimal profile exposes only eval, smoke test, and AST tools" do
    Application.put_env(:tidewave, :tools_profile, :minimal)
    Server.init_tools()

    {tools, dispatch} = Server.tools_and_dispatch()
    tool_names = tool_names(tools)

    assert tool_names == Enum.sort(~w(ast_replace ast_search project_eval smoke_test))
    assert Map.keys(dispatch) |> Enum.sort() == tool_names
  end

  test "custom only profile can expose an explicit tool list" do
    Application.put_env(:tidewave, :tools_profile, {:only, [:project_eval, "smoke_test"]})
    Server.init_tools()

    {tools, _dispatch} = Server.tools_and_dispatch()

    assert tool_names(tools) == ~w(project_eval smoke_test)
  end

  defp tool_names(tools), do: tools |> Enum.map(& &1.name) |> Enum.sort()

  defp restore_profile(nil), do: Application.delete_env(:tidewave, :tools_profile)
  defp restore_profile(profile), do: Application.put_env(:tidewave, :tools_profile, profile)
end
