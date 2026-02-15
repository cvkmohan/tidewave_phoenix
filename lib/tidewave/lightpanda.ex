defmodule Tidewave.Lightpanda do
  @moduledoc """
  Auto-starts Lightpanda headless browser as a supervised Port.
  Returns :ignore if the binary is not in PATH or port is already taken.
  browser_inspect tool checks lightpanda_available?() independently.
  """

  use GenServer

  @port 9222
  @max_restarts 3

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_) do
    case System.find_executable("lightpanda") do
      nil ->
        :ignore

      bin ->
        if port_in_use?() do
          :ignore
        else
          port = start_lightpanda(bin)
          {:ok, %{port: port, bin: bin, restarts: 0}}
        end
    end
  end

  @impl true
  def handle_info({_port, {:exit_status, _status}}, %{restarts: n} = state) when n >= @max_restarts do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({_port, {:exit_status, _status}}, state) do
    Process.sleep(2000)

    if port_in_use?() do
      {:stop, :normal, state}
    else
      port = start_lightpanda(state.bin)
      {:noreply, %{state | port: port, restarts: state.restarts + 1}}
    end
  end

  @impl true
  def handle_info({_port, {:data, _data}}, state) do
    {:noreply, state}
  end

  defp start_lightpanda(bin) do
    port =
      Port.open({:spawn_executable, bin}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["serve", "--host", "127.0.0.1", "--port", "#{@port}"]
      ])

    Process.sleep(500)
    port
  end

  defp port_in_use? do
    case :gen_tcp.connect(~c"127.0.0.1", @port, [], 200) do
      {:ok, sock} ->
        :gen_tcp.close(sock)
        true

      {:error, _} ->
        false
    end
  end
end
