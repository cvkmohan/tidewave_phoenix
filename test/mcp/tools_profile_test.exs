defmodule Tidewave.MCP.ToolsProfileTest do
  use ExUnit.Case, async: true

  alias Tidewave.MCP.ToolsProfile

  @tools Enum.map(~w(project_eval get_logs browser_eval), &%{name: &1})

  test "full preserves upstream tools" do
    assert ToolsProfile.filter(@tools, :full) == @tools
  end

  test "minimal keeps project_eval and upstream browser_eval" do
    assert tool_names(ToolsProfile.filter(@tools, :minimal)) ==
             ~w(project_eval browser_eval)
  end

  test "only and except accept atom and string names" do
    assert tool_names(ToolsProfile.filter(@tools, {:only, [:project_eval, "get_logs"]})) ==
             ~w(project_eval get_logs)

    assert tool_names(ToolsProfile.filter(@tools, {:except, [:get_logs]})) ==
             ~w(project_eval browser_eval)
  end

  test "unknown profiles preserve upstream tools" do
    assert ExUnit.CaptureLog.capture_log(fn ->
             assert ToolsProfile.filter(@tools, :unknown) == @tools
           end) =~ "using :full"
  end

  defp tool_names(tools), do: Enum.map(tools, & &1.name)
end
