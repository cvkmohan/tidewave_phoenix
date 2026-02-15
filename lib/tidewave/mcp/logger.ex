defmodule Tidewave.MCP.Logger do
  @moduledoc false

  use GenServer

  @levels Map.new(~w[emergency alert critical error warning notice info debug]a, &{"#{&1}", &1})

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get_logs(n, opts \\ []) do
    grep = Keyword.get(opts, :grep)
    regex = grep && Regex.compile!(grep, "iu")
    level = Keyword.get(opts, :level)
    level_atom = level && Map.fetch!(@levels, level)
    since = Keyword.get(opts, :since)
    GenServer.call(__MODULE__, {:get_logs, n, regex, level_atom, since})
  end

  @doc """
  Get logs filtered by time. Only returns logs inserted after `since` (DateTime).
  """
  def get_logs_since(n, since, grep \\ nil) do
    regex = grep && Regex.compile!(grep, "iu")
    GenServer.call(__MODULE__, {:get_logs, n, regex, nil, since})
  end

  def clear_logs do
    GenServer.call(__MODULE__, :clear_logs)
  end

  @doc """
  Returns the current timestamp. Agents call this before an operation,
  then pass it as `since` to get only logs from after that point.
  """
  def timestamp do
    DateTime.utc_now()
  end

  # Erlang/OTP log handler
  def log(%{meta: meta, level: level} = event, config) do
    if meta[:tidewave_mcp] do
      :ok
    else
      %{formatter: {formatter_mod, formatter_config}} = config
      chardata = formatter_mod.format(event, formatter_config)
      GenServer.cast(__MODULE__, {:log, level, IO.chardata_to_string(chardata)})
    end
  end

  def init(_) do
    {:ok, %{cb: CircularBuffer.new(1024), timestamps: CircularBuffer.new(1024)}}
  end

  def handle_cast({:log, level, message}, state) do
    # There is a built-in way for MCPs to expose log messages,
    # but we currently don't use it, as the client support isn't really there.
    # https://spec.modelcontextprotocol.io/specification/2024-11-05/server/utilities/logging/
    now = DateTime.utc_now()
    cb = CircularBuffer.insert(state.cb, {level, message})
    ts = CircularBuffer.insert(state.timestamps, now)

    {:noreply, %{state | cb: cb, timestamps: ts}}
  end

  def handle_call({:get_logs, n, regex, level_filter, since}, _from, state) do
    logs = CircularBuffer.to_list(state.cb)
    timestamps = CircularBuffer.to_list(state.timestamps)

    entries =
      Enum.zip(logs, timestamps)
      |> then(fn entries ->
        if since do
          Enum.filter(entries, fn {_log, ts} -> DateTime.compare(ts, since) == :gt end)
        else
          entries
        end
      end)
      |> then(fn entries ->
        if level_filter do
          Enum.filter(entries, fn {{level, _message}, _ts} -> level == level_filter end)
        else
          entries
        end
      end)
      |> then(fn entries ->
        if regex do
          Enum.filter(entries, fn {{_level, message}, _ts} -> Regex.match?(regex, message) end)
        else
          entries
        end
      end)

    result = entries |> Enum.take(-n) |> Enum.map(fn {{_level, message}, _ts} -> message end)

    {:reply, result, state}
  end

  def handle_call(:clear_logs, _from, state) do
    cb = CircularBuffer.new(1024)
    ts = CircularBuffer.new(1024)
    {:reply, :ok, %{state | cb: cb, timestamps: ts}}
  end
end
