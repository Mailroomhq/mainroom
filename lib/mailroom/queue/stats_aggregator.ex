defmodule Mailroom.Queue.StatsAggregator do
  use GenServer

  alias Mailroom.Queue.{Supervisor, Manager}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get_stats(parent_queue_name) do
    GenServer.call(__MODULE__, {:get_stats, parent_queue_name})
  end

  def list_parent_queues do
    GenServer.call(__MODULE__, :list_parent_queues)
  end

  def register_queue(queue_name) do
    GenServer.call(__MODULE__, {:register_queue, queue_name})
  end

  @impl true
  def init(_) do
    initial_state = build_initial_state()

    subscribed_queues =
      Supervisor.list_queues()
      |> MapSet.new()

    Supervisor.list_queues()
    |> Enum.each(fn queue_name ->
      Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue_name}")
    end)

    {:ok, %{stats: initial_state, subscribed: subscribed_queues}}
  end

  @impl true
  def handle_info({Mailroom.Queue.Manager, event, queue_name}, state) do
    parent = parent_queue_name(queue_name)
    new_stats = update_stats(state.stats, parent, event)

    Phoenix.PubSub.broadcast(
      Mailroom.PubSub,
      "queue:#{parent}",
      {__MODULE__, :stats_updated, parent}
    )

    {:noreply, %{state | stats: new_stats}}
  end

  @impl true
  def handle_info({__MODULE__, :stats_updated, _parent_queue}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_call({:register_queue, queue_name}, _from, state) do
    if queue_name in state.subscribed do
      {:reply, :ok, state}
    else
      Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue_name}")

      parent = parent_queue_name(queue_name)
      new_stats = Map.put_new(state.stats, parent, default_stats())
      new_subscribed = MapSet.put(state.subscribed, queue_name)

      {:reply, :ok, %{stats: new_stats, subscribed: new_subscribed}}
    end
  end

  @impl true
  def handle_call(:list_parent_queues, _from, state) do
    {:reply, Map.keys(state.stats), state}
  end

  @impl true
  def handle_call({:get_stats, parent_queue_name}, _from, state) do
    stats = Map.get(state.stats, parent_queue_name, default_stats())
    {:reply, stats, state}
  end

  defp parent_queue_name(queue_name) do
    case String.split(queue_name, ":", parts: 2) do
      [parent, _group_id] -> parent
      [parent] -> parent
    end
  end

  defp build_initial_state do
    Supervisor.list_queues()
    |> Enum.group_by(&parent_queue_name/1)
    |> Enum.map(fn {parent, queue_names} ->
      aggregated_stats =
        Enum.reduce(queue_names, default_stats(), fn queue_name, acc ->
          stats = Manager.stats(queue_name)

          %{
            pending: acc.pending + stats.pending,
            processing: acc.processing + stats.processing,
            completed: acc.completed + stats.completed,
            failed: acc.failed + stats.failed
          }
        end)

      {parent, aggregated_stats}
    end)
    |> Map.new()
  end

  defp default_stats do
    %{pending: 0, processing: 0, completed: 0, failed: 0}
  end

  defp update_stats(state, parent_queue, event) do
    current_stats = Map.get(state, parent_queue, default_stats())

    updated_stats =
      case event do
        :message_enqueued ->
          %{current_stats | pending: current_stats.pending + 1}

        :message_dequeued ->
          %{
            current_stats
            | pending: current_stats.pending - 1,
              processing: current_stats.processing + 1
          }

        :message_processed ->
          %{
            current_stats
            | processing: current_stats.processing - 1,
              completed: current_stats.completed + 1
          }

        :message_requeued ->
          %{
            current_stats
            | processing: current_stats.processing - 1,
              pending: current_stats.pending + 1
          }

        :message_failed ->
          %{
            current_stats
            | processing: current_stats.processing - 1,
              failed: current_stats.failed + 1
          }

        _ ->
          current_stats
      end

    Map.put(state, parent_queue, updated_stats)
  end
end
