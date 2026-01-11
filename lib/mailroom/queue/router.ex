defmodule Mailroom.Queue.Router do
  alias Mailroom.Queue.{Supervisor, Manager}

  def enqueue(queue_name, payload, opts) do
    target_queue =
      case Keyword.get(opts, :group_id) do
        nil -> queue_name
        group_id -> "#{queue_name}:#{group_id}"
      end

    with {:ok, _pid} <- Supervisor.ensure_queue_started(target_queue, opts) do
      Mailroom.Queue.StatsAggregator.register_queue(target_queue)

      Mailroom.Consumer.Manager.ensure_consumer(target_queue)

      Manager.enqueue(target_queue, payload, opts)
    end
  end
end
