defmodule Mailroom.Queue.Router do
  alias Mailroom.Queue.{Supervisor, Manager}

  def enqueue(queue_name, payload, opts) do
    target_queue =
      case Keyword.get(opts, :group_id) do
        nil -> queue_name
        group_id -> "#{queue_name}:#{group_id}"
      end

    # Check if queue already exists to avoid redundant registration calls
    is_new_queue = not Supervisor.queue_exists?(target_queue)

    with {:ok, _pid} <- Supervisor.ensure_queue_started(target_queue, opts) do
      # Only register and start consumer for NEW queues
      if is_new_queue do
        Mailroom.Queue.StatsAggregator.register_queue(target_queue)
        Mailroom.Consumer.Manager.ensure_consumer(target_queue)
      end

      Manager.enqueue(target_queue, payload, opts)
    end
  end
end
