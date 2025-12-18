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
    case Manager.dequeue(state.queue_name) do
      nil ->
        :ok

      message ->
        process_message(message, state.handler, state.queue_name)
    end

    schedule_poll(state.poll_interval)
    {:noreply, state}
  end

  defp process_message(message, handler, queue_name) do
    Logger.debug("Worker processing message #{message.id}")

    try do
      case handler.(message.payload) do
        :ok ->
          Manager.ack(queue_name, message.id)
          Logger.debug("Message #{message.id} acknowledged")

        {:ok, _} ->
          Manager.ack(queue_name, message.id)
          Logger.debug("Message #{message.id} acknowledged")

        _ ->
          Manager.nack(queue_name, message.id)
      end
    rescue
      error ->
        Logger.error("Handler failed for message #{message.id}: #{inspect(error)}")
        Manager.nack(queue_name, message.id)
    end
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
