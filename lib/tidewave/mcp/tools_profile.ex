defmodule Tidewave.MCP.ToolsProfile do
  @moduledoc false

  require Logger

  @minimal_tool_names MapSet.new(~w(project_eval))

  @doc false
  def filter(tools, profile)

  def filter(tools, profile) when profile in [:full, "full", nil], do: tools

  def filter(tools, profile) when profile in [:minimal, "minimal"] do
    Enum.filter(tools, &MapSet.member?(@minimal_tool_names, &1.name))
  end

  def filter(tools, {:only, tool_names}) when is_list(tool_names) do
    tool_names = MapSet.new(tool_names, &to_string/1)
    Enum.filter(tools, &MapSet.member?(tool_names, &1.name))
  end

  def filter(tools, {:except, tool_names}) when is_list(tool_names) do
    tool_names = MapSet.new(tool_names, &to_string/1)
    Enum.reject(tools, &MapSet.member?(tool_names, &1.name))
  end

  def filter(tools, profile) do
    Logger.warning("Unknown Tidewave tools profile #{inspect(profile)}; using :full")
    tools
  end
end
