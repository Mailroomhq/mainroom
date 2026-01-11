defmodule Mailroom.Consumer.Manager do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def register_handler(queue_name, handler) do
    GenServer.call(__MODULE__, {:register_handler, queue_name, handler})
  end

  def ensure_consumer(queue_name) do
    GenServer.call(__MODULE__, {:ensure_consumer, queue_name})
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
      parent_queue = parent_queue_name(queue_name)
      handler = Keyword.fetch!(state.handlers, parent_queue)

      spawn_consumer(queue_name, handler)
      new_active_consumers = MapSet.put(state.active_consumers, queue_name)

      {:reply, :ok, %{state | active_consumers: new_active_consumers}}
    end
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
end
