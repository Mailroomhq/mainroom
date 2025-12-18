defmodule Mailroom.Consumer.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_consumer(queue_name, handler, opts \\ []) do
    concurrency = Keyword.get(opts, :concurrency, 1)
    poll_interval = Keyword.get(opts, :poll_interval, 100)

    Enum.each(1..concurrency, fn _i ->
      child_spec = {
        Mailroom.Consumer.Worker,
        [queue_name: queue_name, handler: handler, poll_interval: poll_interval]
      }

      DynamicSupervisor.start_child(__MODULE__, child_spec)
    end)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
