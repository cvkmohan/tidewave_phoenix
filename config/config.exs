import Config

if config_env() == :test do
  config :tidewave,
    debug: true,
    ecto_repos: [MockRepo, Tidewave.TestRepo]

  config :tidewave, Tidewave.TestRepo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "tidewave_test",
    pool_size: 5,
    log: false
end
