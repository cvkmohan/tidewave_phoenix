defmodule Tidewave.MCP.Tools.AstTest do
  use ExUnit.Case, async: true

  alias Tidewave.MCP.Tools.Ast

  describe "ast_search/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      sample_file = Path.join(tmp_dir, "sample.ex")

      File.write!(
        sample_file,
        """
        defmodule Sample do
          def demo(items, value) do
            mapped = Enum.map(items, &(&1))
            inspected = IO.inspect(value)
            {mapped, inspected}
          end
        end
        """
      )

      {:ok, sample_file: sample_file}
    end

    test "returns invalid_arguments for missing pattern" do
      assert Ast.ast_search(%{}) == {:error, :invalid_arguments}
    end

    test "finds structural matches in a file", %{sample_file: sample_file} do
      assert {:ok, result} =
               Ast.ast_search(%{"pattern" => "IO.inspect(expr)", "path" => sample_file})

      assert result =~ "# AST Search Results"
      assert result =~ "Matches: 1"
      assert result =~ sample_file
      assert result =~ "IO.inspect(value)"
    end

    test "returns a friendly message when there are no matches", %{sample_file: sample_file} do
      assert {:ok, result} =
               Ast.ast_search(%{"pattern" => "String.trim(value)", "path" => sample_file})

      assert result == "No matches found for pattern: `String.trim(value)`"
    end
  end

  describe "ast_replace/1" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      sample_file = Path.join(tmp_dir, "sample.ex")

      File.write!(
        sample_file,
        """
        defmodule Sample do
          def demo(value) do
            inspected = IO.inspect(value)
            inspected
          end
        end
        """
      )

      {:ok, sample_file: sample_file}
    end

    test "returns invalid_arguments for missing replacement" do
      assert Ast.ast_replace(%{"pattern" => "IO.inspect(expr)"}) == {:error, :invalid_arguments}
    end

    test "defaults to dry run and leaves files unchanged", %{sample_file: sample_file} do
      original = File.read!(sample_file)

      assert {:ok, result} =
               Ast.ast_replace(%{
                 "pattern" => "IO.inspect(expr)",
                 "replacement" => "expr",
                 "path" => sample_file
               })

      assert result =~ "# AST Replace Preview (dry run)"
      assert result =~ "Set dry_run to false to apply these changes."
      assert File.read!(sample_file) == original
    end

    test "applies replacements when dry_run is false", %{sample_file: sample_file} do
      assert {:ok, result} =
               Ast.ast_replace(%{
                 "pattern" => "IO.inspect(expr)",
                 "replacement" => "expr",
                 "path" => sample_file,
                 "dry_run" => false
               })

      updated = File.read!(sample_file)

      assert result =~ "# AST Replace Results"
      assert result =~ "Applied 1 replacement(s)"
      refute updated =~ "IO.inspect"
      assert updated =~ "inspected = value"
    end

    test "reports when no replacements are made", %{sample_file: sample_file} do
      assert {:ok, result} =
               Ast.ast_replace(%{
                 "pattern" => "String.trim(expr)",
                 "replacement" => "expr",
                 "path" => sample_file,
                 "dry_run" => false
               })

      assert result == "No replacements made."
    end
  end
end
