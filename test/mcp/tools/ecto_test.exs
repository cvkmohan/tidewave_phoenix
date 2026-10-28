defmodule Tidewave.MCP.Tools.EctoTest do
  use ExUnit.Case, async: true

  alias Tidewave.MCP.Tools.Ecto

  describe "tools/0" do
    test "returns list of tools when repos are configured" do
      assert tools = Ecto.tools()
      assert execute_sql_query = Enum.find(tools, &(&1.name == "execute_sql_query"))
      assert execute_sql_query.inputSchema.properties.repo.description =~ "MockRepo"
      refute Enum.find(tools, &(&1.name == "get_ecto_schemas"))
    end
  end

  describe "execute_sql_query/3" do
    test "uses first repo from list of configured repos when no repo is passed" do
      assert {:ok, _} =
               Ecto.execute_sql_query(
                 %{"query" => "SELECT 1", "arguments" => []},
                 Tidewave.init([])
               )
    end

    test "successfully executes a query" do
      {:ok, text} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "SELECT 1",
            "arguments" => []
          },
          Tidewave.init([])
        )

      assert text =~ "rows: [[1]]"
      assert text =~ "columns: [\"?column?\"]"
    end

    test "handles query with parameters" do
      {:ok, text} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "SELECT $1::text",
            "arguments" => ["test"]
          },
          Tidewave.init([])
        )

      assert text =~ "rows: [[\"test\"]]"
    end

    test "truncates rows" do
      {:ok, text} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "SELECT lotsofrows",
            "arguments" => []
          },
          Tidewave.init([])
        )

      assert text =~ "Query returned 100 rows. Only the first 50 rows are included in the result."
      assert text =~ "42"
    end

    test "returns error for failed query" do
      {:error, message} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "ERROR",
            "arguments" => []
          },
          Tidewave.init([])
        )

      assert message =~ "Failed to execute query"
      assert message =~ "Query error"
    end

    test "prints charlists as lists by default" do
      {:ok, text} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "SELECT charlist",
            "arguments" => []
          },
          Tidewave.init([])
        )

      assert text =~ "rows: [97, 98, 99]"
    end

    test "inspect_opts" do
      {:ok, text} =
        Ecto.execute_sql_query(
          %{
            "repo" => "MockRepo",
            "query" => "SELECT lotsofrows",
            "arguments" => []
          },
          Tidewave.init([])
        )

      assert text =~ "Query returned 100 rows. Only the first 50 rows are included in the result."
      refute text =~ "51"
    end
  end

  describe "read-only enforcement" do
    @repo "Tidewave.TestRepo"

    setup do
      Tidewave.TestRepo.query!("DROP TABLE IF EXISTS tidewave_ro_test")
      Tidewave.TestRepo.query!("CREATE TABLE tidewave_ro_test (id int PRIMARY KEY, name text)")
      Tidewave.TestRepo.query!("INSERT INTO tidewave_ro_test VALUES (1, 'one')")
      on_exit(fn -> Tidewave.TestRepo.query!("DROP TABLE IF EXISTS tidewave_ro_test") end)
    end

    defp run(query, arguments \\ []) do
      Ecto.execute_sql_query(
        %{"repo" => @repo, "query" => query, "arguments" => arguments},
        Tidewave.init([])
      )
    end

    defp rows,
      do: Tidewave.TestRepo.query!("SELECT id, name FROM tidewave_ro_test ORDER BY id").rows

    test "a SELECT works" do
      assert {:ok, text} = run("SELECT name FROM tidewave_ro_test WHERE id = $1", [1])
      assert text =~ ~s|rows: [["one"]]|
    end

    test "writes fail with a read-only message and persist nothing" do
      for query <- [
            "INSERT INTO tidewave_ro_test VALUES (2, 'two')",
            "UPDATE tidewave_ro_test SET name = 'changed'",
            "DELETE FROM tidewave_ro_test",
            "CREATE TABLE tidewave_ro_other (id int)",
            "ALTER TABLE tidewave_ro_test ADD COLUMN extra int",
            "DROP TABLE tidewave_ro_test",
            "TRUNCATE tidewave_ro_test"
          ] do
        assert {:error, message} = run(query)
        assert message =~ "Failed to execute query"
        assert message =~ "read-only", "no read-only hint for #{query}"
      end

      assert rows() == [[1, "one"]]

      assert {:ok, %{rows: [[nil]]}} =
               Tidewave.TestRepo.query("SELECT to_regclass('tidewave_ro_other')")
    end

    test "SET TRANSACTION READ WRITE cannot lift the restriction" do
      assert {:error, _} = run("SET TRANSACTION READ WRITE")
      assert {:error, _} = run("SET transaction_read_only = off")
      assert {:error, _} = run("SELECT set_config('transaction_read_only', 'off', true)")
      assert {:error, message} = run("SELECT nextval('tidewave_ro_missing_seq')")
      assert message =~ "Failed to execute query"
      assert rows() == [[1, "one"]]
    end

    test "COMMIT and ROLLBACK statements persist nothing" do
      run("COMMIT")
      run("ROLLBACK")
      run("INSERT INTO tidewave_ro_test VALUES (3, 'three')")
      assert rows() == [[1, "one"]]
    end

    test "the repo is usable for writes outside the tool afterwards" do
      run("SELECT 1")
      Tidewave.TestRepo.query!("INSERT INTO tidewave_ro_test VALUES (4, 'four')")
      assert length(rows()) == 2
    end
  end

  describe "adapters other than PostgreSQL" do
    test "are refused without running the query" do
      assert {:error, message} =
               Ecto.execute_sql_query(
                 %{"repo" => "MockMySQLRepo", "query" => "SELECT 1"},
                 Tidewave.init([])
               )

      assert message =~ "read-only"
      assert message =~ "MockMySQLRepo"
    end
  end
end
