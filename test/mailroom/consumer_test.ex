defmodule Mailroom.ConsumerTest do
  use ExUnit.Case
  alias Mailroom.Queue.Manager
  alias Mailroom.Consumer

  test "consumer processes messages from queue" do
    queue_name = "test_queue_#{:rand.uniform(1_000_000)}"
    test_pid = self()

    handler = fn payload ->
      send(test_pid, {:processed, payload})
      :ok
    end

    {:ok, _pid} = Mailroom.Queue.Supervisor.ensure_queue_started(queue_name)

    Consumer.start(
      queue_name: queue_name,
      handler: handler,
      concurrency: 1
    )

    {:ok, _message} = Manager.enqueue(queue_name, "Hello")

    assert_receive {:processed, "Hello"}, 1000
  end
end
