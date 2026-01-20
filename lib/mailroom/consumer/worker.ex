defmodule Mailroom.Consumer.Worker do
  alias Mailroom.Queue.Manager
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    queue_name = Keyword.get(opts, :queue_name)
    handler = Keyword.get(opts, :handler)
    poll_interval = Keyword.get(opts, :poll_interval, 100)

    state = %{
      queue_name: queue_name,
      handler: handler,
      poll_interval: poll_interval
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    case safe_dequeue(state.queue_name) do
      {:ok, nil} ->
        # No messages, keep polling
        schedule_poll(state.poll_interval)
        {:noreply, state}

      {:ok, message} ->
        # Got a message, process it
        process_message(message, state.handler, state.queue_name)
        schedule_poll(state.poll_interval)
        {:noreply, state}

      {:error, :queue_not_found} ->
        # Queue was deleted, shut down gracefully
        Logger.info("Queue #{state.queue_name} no longer exists, stopping worker")
        {:stop, :normal, state}
    end
  end

  defp safe_dequeue(queue_name) do
    try do
      {:ok, Manager.dequeue(queue_name)}
    catch
      :exit, _ ->
        {:error, :queue_not_found}
    end
  end

  defp process_message(message, handler, queue_name) do
    Logger.debug("Worker processing message #{message.id}")

    try do
      case handler.(message.payload) do
        :ok ->
          safe_ack(queue_name, message.id)
          Logger.debug("Message #{message.id} acknowledged")

        {:ok, _} ->
          safe_ack(queue_name, message.id)
          Logger.debug("Message #{message.id} acknowledged")

        _ ->
          safe_nack(queue_name, message.id)
      end
    rescue
      error ->
        Logger.error("Handler failed for message #{message.id}: #{inspect(error)}")
        safe_nack(queue_name, message.id)
    end
  end

  defp safe_ack(queue_name, message_id) do
    try do
      Manager.ack(queue_name, message_id)
    catch
      :exit, _ -> :ok
    end
  end

  defp safe_nack(queue_name, message_id) do
    try do
      Manager.nack(queue_name, message_id)
    catch
      :exit, _ -> :ok
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
