defmodule Tidewave.MixProject do
  use Mix.Project

  @source_url "https://github.com/cvkmohan/tidewave_phoenix"
  @homepage_url "https://github.com/cvkmohan/tidewave_phoenix"
  @version "0.9.2"

  def project do
    [
      app: :tidewave,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      aliases: [
        tidewave:
          "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
      ],

      # Docs
      name: "Tidewave",
      source_url: @source_url,
      homepage_url: @homepage_url,
      docs: &docs/0
    ]
  end

  def application do
    [
      mod: {Tidewave.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      description: "Tidewave for Phoenix",
      maintainers: ["Steffen Deusch"],
      licenses: ["Apache-2.0"],
      links: %{
        "Tidewave" => @homepage_url,
        "GitHub" => @source_url
      }
    ]
  end

  defp deps do
    [
      {:plug, "~> 1.18"},
      {:jason, "~> 1.4"},
      {:circular_buffer, "~> 0.4 or ~> 1.0"},
      {:igniter, "~> 0.6", optional: true},

      # We require v1.6.1 to detect if phoenix live reload is running too early or late
      {:phoenix_live_reload, ">= 1.6.1", optional: true},

      # Dev deps
      {:bandit, "~> 1.10", only: [:dev, :test]},
      {:ecto_sql, "~> 3.12", only: :test},
      {:postgrex, "~> 0.19", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:makeup_syntect, ">= 0.0.0", only: :dev}
    ]
  end

  defp docs do
    [
      api_reference: false,
      main: "readme",
      logo: "logo.svg",
      footer: false,
      assets: %{"pages/assets" => "assets"},
      filter_modules: fn mod, _ ->
        raise "you forgot to add \"@moduledoc false\" to #{inspect(mod)}"
      end,
      extras: [
        "README.md",
        "pages/references/security.md",
        "pages/mcp/mcp.md",
        "pages/mcp/mcp_claude_code.md",
        "pages/mcp/mcp_cursor.md",
        "pages/mcp/mcp_neovim.md",
        "pages/mcp/mcp_codex.md",
        "pages/mcp/mcp_opencode.md",
        "pages/mcp/mcp_vscode.md"
      ],
      groups_for_extras: [
        Welcome: "README.md",
        "Tidewave MCP": ~r/pages\/mcp\/.?/,
        References: ~r/(pages\/references\/.?)/
      ],
      redirects: %{
        "mcp_troubleshooting" => "mcp",
        "subdomains" => "mcp"
      },
      before_closing_head_tag: fn _ ->
        # Hide version nodes to avoid confusion between TidewaveApp and TidewavePhoenix.
        # But we still keep go to latest.
        "<style>.sidebar-projectVersion form label { display: none; }</style>"
      end
    ]
  end
end
