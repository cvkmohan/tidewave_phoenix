{:ok, _} = Application.ensure_all_started(:inets)
{:ok, _} = Application.ensure_all_started(:postgrex)
{:ok, _} = Tidewave.TestRepo.start_link()

ExUnit.start()
