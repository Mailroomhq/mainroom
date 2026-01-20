defmodule Mailroom.Consumer.Manager do
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_handler(queue_name, handler) do
    GenServer.call(__MODULE__, {:register_handler, queue_name, handler})
  end

  def ensure_consumer(queue_name) do
    GenServer.call(__MODULE__, {:ensure_consumer, queue_name}, 10_000)
  end

  def stop_consumer(queue_name) do
    GenServer.call(__MODULE__, {:stop_consumer, queue_name})
  end

  def reset do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_) do
    {:ok, %{handlers: {}, active_consumers: MapSet.new()}}
  end

  @impl true
  def handle_call({:register_handler, parent_queue, handler}, _from, state) do
    {:reply, :ok, %{state | parent_queue: parent_queue, handler: handler}}
  end

  @impl true
  def handle_call({:ensure_consumer, queue_name}, _from, state) do
    if queue_name in state.active_consumers do
      {:reply, :ok, state}
    else
      parent = parent_queue_name(queue_name)

      case find_handler(parent) do
        {:ok, handler} ->
          spawn_consumer(queue_name, handler)
          new_active = MapSet.put(state.active_consumers, queue_name)
          {:reply, :ok, %{state | active_consumers: new_active}}

        {:error, reason} ->
          Logger.warning("No handler found for queue #{parent}: #{reason}")
          {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call({:stop_consumer, queue_name}, _from, state) do
    new_active = MapSet.delete(state.active_consumers, queue_name)

    {:reply, :ok, %{state | active_consumers: new_active}}
  end

  @impl true
  def handle_call(:reset, _from, state) do
    {:reply, :ok, %{state | active_consumers: MapSet.new()}}
  end

  defp parent_queue_name(queue_name) do
    case String.split(queue_name, ":", parts: 2) do
      [parent, _group_id] -> parent
      [parent] -> parent
    end
  end

  defp spawn_consumer(queue_name, handler) do
    Mailroom.Consumer.Supervisor.start_consumer(queue_name, handler, concurrency: 1)
  end

  defp find_handler(parent_queue) do
    module_name =
      parent_queue
      |> Macro.camelize()
      |> then(&Module.concat(Mailroom.Handlers, &1))

    if Code.ensure_loaded?(module_name) and
         function_exported?(module_name, :handle, 1) do
      {:ok, Function.capture(module_name, :handle, 1)}
    else
      {:error, "Module #{module_name} not found or missing handle/1 function"}
    end
  end
end
