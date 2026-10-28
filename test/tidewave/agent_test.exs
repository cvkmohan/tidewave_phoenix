defmodule Tidewave.AgentTest do
  use ExUnit.Case, async: true

  require Logger

  test "reports project runtime information" do
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
  test "delegates structured log access" do
    cutoff = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.to_iso8601()
    Logger.info("agent facade log")

    assert {:ok, logs} = Tidewave.Agent.logs(tail: 10, grep: "facade", since: cutoff)
    assert logs =~ "agent facade log"
  end

  test "delegates SQL, docs, and source inspection" do
    assert {:ok, result} = Tidewave.Agent.sql("SELECT 1", repo: "MockRepo")
    assert result =~ "rows: [[1]]"

    assert {:ok, docs} = Tidewave.Agent.docs(String)
    assert docs =~ "Strings in Elixir"

    assert {:ok, source} = Tidewave.Agent.source(Tidewave)
    assert source =~ "lib/tidewave.ex"
  end

  test "reports the absence of Phoenix routes cleanly" do
    assert {:error, "No Phoenix routes found"} = Tidewave.Agent.routes()
  end
end
