defmodule Mailroom.Queue.Janitor do
  use GenServer
  require Logger

  alias Mailroom.Queue.{Supervisor, Manager}
  alias Mailroom.Queue.StatsAggregator
  alias Mailroom.Consumer.Manager, as: ConsumerManager

  @cleanup_interval :timer.minutes(5)

  @idle_threshold_ms :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def run_cleanup do
    GenServer.call(__MODULE__, :run_cleanup)
  end

  @impl true
  def init(_) do
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_idle_queues()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_call(:run_cleanup, _from, state) do
    count = cleanup_idle_queues()
    {:reply, {:ok, count}, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_idle_queues do
    Supervisor.list_queues()
    |> Enum.filter(&is_group_queue?/1)
    |> Enum.filter(&should_cleanup?/1)
    |> Enum.map(&cleanup_queue/1)
    |> length()
  end

  defp is_group_queue?(queue_name) do
    String.contains?(queue_name, ":")
  end

  defp should_cleanup?(queue_name) do
    stats = Manager.stats(queue_name)
    last_activity = Manager.last_activity(queue_name)

    is_empty = stats.pending == 0 and stats.processing == 0
    idle_duration = DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)
    is_idle = idle_duration > @idle_threshold_ms

    is_empty && is_idle
  end

  defp cleanup_queue(queue_name) do
    Logger.info("Cleaning up idle queue: #{queue_name}")

    ConsumerManager.stop_consumer(queue_name)
    StatsAggregator.unregister_queue(queue_name)
    Supervisor.stop_queue(queue_name)

    queue_name
  end
end
