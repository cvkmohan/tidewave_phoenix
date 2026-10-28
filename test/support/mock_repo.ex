defmodule MockRepo do
  def __adapter__ do
    Ecto.Adapters.Postgres
  end

  def transaction(fun) do
    {:ok, fun.()}
  catch
    {:mock_rollback, value} -> {:error, value}
  end

  def rollback(value), do: throw({:mock_rollback, value})

  def query("SET TRANSACTION READ ONLY", []), do: {:ok, %{rows: [], columns: nil}}

  def query("SELECT 1", []) do
    {:ok, %{rows: [[1]], columns: ["?column?"]}}
  end

  def query("SELECT $1::text", ["test"]) do
    {:ok, %{rows: [["test"]], columns: ["?column?"]}}
  end

  def query("ERROR", _) do
    {:error, %{message: "Query error"}}
  end

  def query("SELECT lotsofrows", _) do
    {:ok, %{rows: Enum.to_list(1..100), num_rows: 100, columns: ["?column?"]}}
  end

  def query("SELECT charlist", _) do
    {:ok, %{rows: ~c"abc", num_rows: 3, columns: ["?column?"]}}
  end
end

defmodule MockMySQLRepo do
  def __adapter__, do: Ecto.Adapters.MyXQL

  def query(_query, _args), do: raise("must not be called")
end

defmodule Tidewave.TestRepo do
  use Ecto.Repo, otp_app: :tidewave, adapter: Ecto.Adapters.Postgres
end
