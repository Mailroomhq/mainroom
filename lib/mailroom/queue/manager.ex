defmodule Mailroom.Queue.Manager do
  use GenServer
  require Logger

  alias Expo.Message
  alias Expo.Message
  alias Mailroom.Queue.Message

  @type queue_name :: String.t()
  @type message_id :: String.t()

  def start_link(opts) do
    queue_name = Keyword.fetch!(opts, :queue_name)
    GenServer.start_link(__MODULE__, queue_name, name: via_tuple(queue_name))
  end

  def enqueue(queue_name, payload, opts \\ []) do
    GenServer.call(via_tuple(queue_name), {:enqueue, payload, opts})
  end

  def dequeue(queue_name) do
    GenServer.call(via_tuple(queue_name), :dequeue)
  end

  def ack(queue_name, message_id) do
    GenServer.call(via_tuple(queue_name), {:ack, message_id})
  end

  def nack(queue_name, message_id) do
    GenServer.call(via_tuple(queue_name), {:nack, message_id})
  end

  def stats(queue_name) do
    GenServer.call(via_tuple(queue_name), :stats)
  end

  def list_messages(queue_name, status \\ :all) do
    GenServer.call(via_tuple(queue_name), {:list_messages, status})
  end

  defp via_tuple(queue_name) do
    {:via, Registry, {Mailroom.Queue.Registry, queue_name}}
  end

  @impl true
  def init(queue_name) do
    Logger.info("Starting queue manager for: #{queue_name}")

    messages_table = :ets.new(:messages, [:set, :protected])
    pending_table = :ets.new(:pending, [:ordered_set, :protected])
    processing_table = :ets.new(:processing, [:set, :protected])

    state = %{
      queue_name: queue_name,
      messages_table: messages_table,
      pending_table: pending_table,
      processing_table: processing_table,
      stats: %{
        enqueued: 0,
        dequeued: 0,
        acknowledged: 0,
        failed: 0
      }
    }

    schedule_timeout_check()

    {:ok, state}
  end

  @impl true
  def handle_call({:enqueue, payload, opts}, _from, state) do
    message = Message.new(state.queue_name, payload, opts)

    :ets.insert(state.messages_table, {message.id, message})

    :ets.insert(state.pending_table, {message.inserted_at, message.id})

    new_state = update_in(state, [:stats, :enqueued], &(&1 + 1))

    Logger.debug("Enqueued message #{message.id} to queue #{state.queue_name}")

    broadcast_queue_event(state.queue_name, :message_enqueued)

    {:reply, {:ok, message}, new_state}
  end

  @impl true
  def handle_call(:dequeue, _from, state) do
    case :ets.first(state.pending_table) do
      :"$end_of_table" ->
        {:reply, nil, state}

      timestamp ->
        [{^timestamp, message_id}] =
          :ets.lookup(state.pending_table, timestamp)

        :ets.delete(state.pending_table, timestamp)

        [{^message_id, message}] =
          :ets.lookup(state.messages_table, message_id)

        updated_message =
          Message.mark_processing(message)

        :ets.insert(state.messages_table, {message_id, updated_message})

        :ets.insert(state.processing_table, {message_id, DateTime.utc_now()})

        new_state = update_in(state, [:stats, :dequeued], &(&1 + 1))

        Logger.debug("Dequeued message #{message_id} from queue #{state.queue_name}")

        broadcast_queue_event(state.queue_name, :message_dequeued)

        {:reply, updated_message, new_state}
    end
  end

  @impl true
  def handle_call({:ack, message_id}, _from, state) do
    case :ets.lookup(state.messages_table, message_id) do
      [{^message_id, message}] ->
        updated_message = Message.mark_completed(message)
        :ets.insert(state.messages_table, {message_id, updated_message})

        :ets.delete(state.processing_table, message_id)

        new_state = update_in(state, [:stats, :acknowledged], &(&1 + 1))

        Logger.debug("Acknowledged message #{message_id} in queue #{state.queue_name}")

        broadcast_queue_event(state.queue_name, :message_processed)

        {:reply, :ok, new_state}

      [] ->
        Logger.warning("Attempted to ack non-existent message #{message_id}")

        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:nack, message_id}, _from, state) do
    case :ets.lookup(state.messages_table, message_id) do
      [{^message_id, message}] ->
        updated_message = Message.mark_failed(message)
        :ets.insert(state.messages_table, {message_id, updated_message})

        :ets.delete(state.processing_table, message_id)

        if updated_message.status == :pending do
          :ets.insert(state.pending_table, {DateTime.utc_now(), message_id})

          Logger.debug(
            "Message #{message_id} returned to pending (attempt #{updated_message.attempts})"
          )

          broadcast_queue_event(state.queue_name, :message_requeued)

          {:reply, :ok, state}
        else
          new_state = update_in(state, [:stats, :failed], &(&1 + 1))

          Logger.warning(
            "Message #{message_id} permanently failed after #{updated_message.attempts} attempts"
          )

          broadcast_queue_event(state.queue_name, :message_failed)
          {:reply, :ok, new_state}
        end

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, state) do
    pending_count = :ets.info(state.pending_table, :size)
    processing_count = :ets.info(state.processing_table, :size)
    total_messages = :ets.info(state.messages_table, :size)

    completed_count = count_by_status(state.messages_table, :completed)
    failed_count = count_by_status(state.messages_table, :failed)

    stats = %{
      pending: pending_count,
      processing: processing_count,
      completed: completed_count,
      failed: failed_count,
      total: total_messages,
      counters: state.stats
    }

    {:reply, stats, state}
  end

  def handle_call({:list_messages, status}, _from, state) do
    messages =
      state.messages_table
      |> :ets.tab2list()
      |> Enum.map(fn {_id, message} -> message end)
      |> filter_by_status(status)

    {:reply, messages, state}
  end

  @impl true
  def handle_info(:check_timeouts, state) do
    processing_messages = :ets.tab2list(state.processing_table)

    Enum.each(processing_messages, fn {message_id, _started_at} ->
      case :ets.lookup(state.messages_table, message_id) do
        [{^message_id, message}] ->
          if Message.timed_out?(message) do
            Logger.warning("Message #{message_id} timed out, returning to queue")
            GenServer.cast(self(), {:timeout, message_id})
          end

        [] ->
          :ets.delete(state.processing_table, message_id)
      end
    end)

    schedule_timeout_check()
    {:noreply, state}
  end

  @impl true
  def handle_cast({:timeout, message_id}, state) do
    case :ets.lookup(state.messages_table, message_id) do
      [{^message_id, message}] ->
        updated_message = Message.mark_failed(message)
        :ets.insert(state.messages_table, {message_id, updated_message})
        :ets.delete(state.processing_table, message_id)

        if updated_message.status == :pending do
          :ets.insert(state.pending_table, {DateTime.utc_now(), message_id})
        end

      [] ->
        :ok
    end

    {:noreply, state}
  end

  defp schedule_timeout_check do
    Process.send_after(self(), :check_timeouts, 5_000)
  end

  defp count_by_status(table, status) do
    :ets.foldl(
      fn {_id, message}, acc ->
        if message.status == status,
          do: acc + 1,
          else: acc
      end,
      0,
      table
    )
  end

  defp filter_by_status(messages, :all), do: messages

  defp filter_by_status(messages, status) do
    Enum.filter(messages, fn message -> message.status == status end)
  end

  defp broadcast_queue_event(queue_name, event) do
    Phoenix.PubSub.broadcast(
      Mailroom.PubSub,
      "queue:#{queue_name}",
      {__MODULE__, event, queue_name}
    )
  end
end
