defmodule Tidewave.MCP.Tools.JsHooksTest do
  use ExUnit.Case, async: true

  alias Tidewave.MCP.Tools.JsHooks

  test "evaluates JavaScript with browser APIs" do
    assert {:ok, "3"} = JsHooks.eval_js(%{"code" => "1 + 2"})

    assert {:ok, "DIV"} =
             JsHooks.eval_js(%{"code" => "document.createElement('div').tagName"})
  end

  test "returns JavaScript errors" do
    assert {:error, "JS error: " <> message} =
             JsHooks.eval_js(%{"code" => "throw new Error('boom')"})

    assert message =~ "boom"
  end
end
