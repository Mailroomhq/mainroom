defmodule Mailroom.Consumer do
  @moduledoc """
  API for starting message consumers.
  """

  alias Mailroom.Consumer.Supervisor

  @doc """
  Starts consumer workers for a queue.

  ## Options
  - `:queue_name` (required) - Name of the queue to consume from
  - `:handler` (required) - Function to process messages (receives payload)
  - `:concurrency` (optional) - Number of workers (default: 1)
  - `:poll_interval` (optional) - Milliseconds between polls (default: 100)

  ## Example
    Mailroom.Consumer.start(
      queue_name: "emails",
      handler: &MyApp.process_email/1,
      concurrency: 5
  )
  """
  def start(opts) do
    queue_name = Keyword.fetch!(opts, :queue_name)
    handler = Keyword.fetch!(opts, :handler)

    worker_opts = Keyword.drop(opts, [:concurrency, :poll_interval])

    Supervisor.start_consumer(queue_name, handler, worker_opts)
  end
end
