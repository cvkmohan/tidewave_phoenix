defmodule Tidewave.AgentTest do
  use ExUnit.Case, async: true

  require Logger

  test "project returns runtime metadata" do
    assert %{
             root: root,
             project_name: project_name,
             mix_project: :tidewave,
             mix_env: :test,
             elixir: elixir,
             otp: otp
           } = Tidewave.Agent.project()

    assert is_binary(root)
    assert is_binary(project_name)
    assert is_binary(elixir)
    assert is_binary(otp)
  end

  @tag :capture_log
  test "logs wraps captured MCP logs" do
    Logger.error("agent facade log witness")

    assert {:ok, logs} = Tidewave.Agent.logs(tail: 10, grep: "facade")
    assert logs =~ "agent facade log witness"
  end

  test "sql wraps configured Ecto repos" do
    assert {:ok, result} = Tidewave.Agent.sql("SELECT 1", repo: "MockRepo")
    assert result =~ "rows: [[1]]"
  end

  test "docs and source wrap BEAM documentation/source lookup" do
    assert {:ok, docs} = Tidewave.Agent.docs(String)
    assert docs =~ "Strings in Elixir"

    assert {:ok, source} = Tidewave.Agent.source(Tidewave)
    assert source =~ "lib/tidewave.ex"
  end

  test "component and module helpers wrap Phoenix introspection tools" do
    assert {:ok, functions} = Tidewave.Agent.module_functions(Tidewave)
    assert functions =~ "Public Functions"

    assert {:ok, component} = Tidewave.Agent.component({Phoenix.Component, :form})
    assert component =~ "Phoenix.Component.form"
  end

  test "frontend helpers expose detected toolchain and checks" do
    assert {:ok, status} = Tidewave.Agent.frontend_status()

    assert %{
             root: root,
             toolchain: toolchain,
             checks: checks,
             volt: volt,
             aliases: aliases,
             package_json?: package_json?,
             vite_config?: vite_config?
           } = status

    assert is_binary(root)
    assert toolchain in [:volt, :vite, :phoenix_default, :unknown]
    assert is_list(checks)
    assert is_map(volt)
    assert is_map(aliases)
    assert is_boolean(package_json?)
    assert is_boolean(vite_config?)

    assert {:ok, check} = Tidewave.Agent.frontend_check()
    assert %{toolchain: ^toolchain, checks: ^checks, note: note} = check
    assert note =~ "run: true"
  end
end
