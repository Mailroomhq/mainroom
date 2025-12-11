defmodule Mailroom.Queue.ManagerTest do
  use ExUnit.Case, async: true

  alias Mailroom.Queue.Manager
  alias Mailroom.Queue.Message

  setup do
    # Generate unique queue name for each test to avoid conflicts
    queue_name = "test_queue_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Manager.start_link(queue_name: queue_name)

    # Stop the queue after each test
    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{queue_name: queue_name, pid: pid}
  end

  describe "enqueue/3" do
    test "enqueues a message and returns ok tuple", %{queue_name: queue_name} do
      payload = %{task: "send_email", to: "user@example.com"}
      assert {:ok, %Message{} = message} = Manager.enqueue(queue_name, payload)
      assert message.payload == payload
      assert message.status == :pending
      assert message.queue_name == queue_name
    end

    test "increments stats when message is enqueued", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "payload1")
      Manager.enqueue(queue_name, "payload2")

      stats = Manager.stats(queue_name)
      assert stats.pending == 2
    end

    test "supports custom max_attempts option", %{queue_name: queue_name} do
      {:ok, message} = Manager.enqueue(queue_name, "test", max_attempts: 5)
      assert message.max_attempts == 5
    end

    test "supports custom timeout_ms option", %{queue_name: queue_name} do
      {:ok, message} = Manager.enqueue(queue_name, "test", timeout_ms: 60_000)
      assert message.timeout_ms == 60_000
    end
  end

  describe "dequeue/1" do
    test "returns nil when queue is empty", %{queue_name: queue_name} do
      assert Manager.dequeue(queue_name) == nil
    end

    test "dequeues messages in FIFO order", %{queue_name: queue_name} do
      {:ok, msg1} = Manager.enqueue(queue_name, "first")
      {:ok, msg2} = Manager.enqueue(queue_name, "second")
      {:ok, msg3} = Manager.enqueue(queue_name, "third")

      assert %Message{payload: "first"} = Manager.dequeue(queue_name)
      assert %Message{payload: "second"} = Manager.dequeue(queue_name)
      assert %Message{payload: "third"} = Manager.dequeue(queue_name)
      assert Manager.dequeue(queue_name) == nil
    end

    test "marks message as processing", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test")
      message = Manager.dequeue(queue_name)

      assert message.status == :processing
      assert message.attempts == 1
      assert message.processing_started_at != nil
    end

    test "updates stats to show processing message", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test")
      Manager.dequeue(queue_name)

      stats = Manager.stats(queue_name)
      assert stats.pending == 0
      assert stats.processing == 1
    end
  end

  describe "ack/2" do
    test "marks message as completed", %{queue_name: queue_name} do
      {:ok, msg} = Manager.enqueue(queue_name, "test")
      dequeued = Manager.dequeue(queue_name)

      assert :ok = Manager.ack(queue_name, dequeued.id)

      stats = Manager.stats(queue_name)
      assert stats.completed == 1
      assert stats.processing == 0
    end

    test "removes message from processing table", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test")
      msg = Manager.dequeue(queue_name)
      Manager.ack(queue_name, msg.id)

      stats = Manager.stats(queue_name)
      assert stats.processing == 0
    end

    test "acknowledging non-existent message returns error", %{queue_name: queue_name} do
      assert {:error, :not_found} = Manager.ack(queue_name, "nonexistent_id")
    end
  end

  describe "nack/2" do
    test "returns message to pending queue on first failure", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test")
      msg = Manager.dequeue(queue_name)

      assert :ok = Manager.nack(queue_name, msg.id)

      stats = Manager.stats(queue_name)
      assert stats.pending == 1
      assert stats.processing == 0
    end

    test "increments attempt counter", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test")
      msg1 = Manager.dequeue(queue_name)
      assert msg1.attempts == 1

      Manager.nack(queue_name, msg1.id)
      msg2 = Manager.dequeue(queue_name)
      assert msg2.attempts == 2
    end

    test "marks message as failed after max_attempts", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "test", max_attempts: 3)

      # Attempt 1
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)

      # Attempt 2
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)

      # Attempt 3 - should fail permanently
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)

      stats = Manager.stats(queue_name)
      assert stats.failed == 1
      assert stats.pending == 0
    end

    test "nacking non-existent message returns error", %{queue_name: queue_name} do
      assert {:error, :not_found} = Manager.nack(queue_name, "nonexistent_id")
    end
  end

  describe "stats/1" do
    test "returns initial stats with all zeros", %{queue_name: queue_name} do
      stats = Manager.stats(queue_name)

      assert stats.pending == 0
      assert stats.processing == 0
      assert stats.completed == 0
      assert stats.failed == 0
      assert stats.total == 0
      assert stats.counters.enqueued == 0
      assert stats.counters.dequeued == 0
      assert stats.counters.acknowledged == 0
      assert stats.counters.failed == 0
    end

    test "tracks permanent failures correctly", %{queue_name: queue_name} do
      # Enqueue one message
      Manager.enqueue(queue_name, "will_fail", max_attempts: 3)

      # Fail it 3 times
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)

      # Should be marked as failed
      stats = Manager.stats(queue_name)
      assert stats.failed == 1
      assert stats.pending == 0
      assert stats.processing == 0
    end

    test "tracks message lifecycle correctly", %{queue_name: queue_name} do
      # Enqueue 3 messages
      Manager.enqueue(queue_name, "msg1")
      Manager.enqueue(queue_name, "msg2")
      Manager.enqueue(queue_name, "msg3")

      assert Manager.stats(queue_name).pending == 3

      # Process one successfully
      msg1 = Manager.dequeue(queue_name)
      assert Manager.stats(queue_name).processing == 1
      Manager.ack(queue_name, msg1.id)
      assert Manager.stats(queue_name).completed == 1

      # Dequeue the second message and complete it
      msg2 = Manager.dequeue(queue_name)
      Manager.ack(queue_name, msg2.id)

      # Final stats: 2 completed, 1 pending
      final_stats = Manager.stats(queue_name)
      assert final_stats.pending == 1
      assert final_stats.processing == 0
      assert final_stats.completed == 2
    end
  end

  describe "list_messages/2" do
    test "lists all messages when status is :all", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "msg1")
      Manager.enqueue(queue_name, "msg2")

      messages = Manager.list_messages(queue_name, :all)
      assert length(messages) == 2
    end

    test "filters messages by pending status", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "pending1")
      Manager.enqueue(queue_name, "pending2")
      msg = Manager.dequeue(queue_name)

      pending = Manager.list_messages(queue_name, :pending)
      assert length(pending) == 1
      assert hd(pending).payload == "pending2"
    end

    test "filters messages by processing status", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "msg1")
      Manager.enqueue(queue_name, "msg2")
      Manager.dequeue(queue_name)

      processing = Manager.list_messages(queue_name, :processing)
      assert length(processing) == 1
      assert hd(processing).payload == "msg1"
    end

    test "filters messages by completed status", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "msg1")
      msg = Manager.dequeue(queue_name)
      Manager.ack(queue_name, msg.id)

      completed = Manager.list_messages(queue_name, :completed)
      assert length(completed) == 1
      assert hd(completed).status == :completed
    end

    test "filters messages by failed status", %{queue_name: queue_name} do
      Manager.enqueue(queue_name, "fail_me", max_attempts: 1)
      msg = Manager.dequeue(queue_name)
      Manager.nack(queue_name, msg.id)

      failed = Manager.list_messages(queue_name, :failed)
      assert length(failed) == 1
      assert hd(failed).status == :failed
    end
  end

  describe "timeout handling" do
    test "messages that exceed timeout are returned to queue", %{queue_name: queue_name} do
      # Enqueue with very short timeout
      Manager.enqueue(queue_name, "timeout_test", timeout_ms: 100)
      msg = Manager.dequeue(queue_name)

      # Message should not be timed out immediately after dequeue
      assert Message.timed_out?(msg) == false

      # Wait for timeout
      Process.sleep(150)

      # After waiting longer than timeout, message should be detected as timed out
      assert Message.timed_out?(msg) == true

      # Create a message with processing started 1 second ago
      updated_msg = %{msg | processing_started_at: DateTime.add(DateTime.utc_now(), -1, :second)}
      assert Message.timed_out?(updated_msg) == true
    end
  end

  describe "concurrent operations" do
    test "handles concurrent enqueues safely", %{queue_name: queue_name} do
      # Spawn multiple processes enqueueing simultaneously
      tasks =
        1..100
        |> Enum.map(fn i ->
          Task.async(fn ->
            Manager.enqueue(queue_name, "msg_#{i}")
          end)
        end)

      results = Task.await_many(tasks)

      assert length(results) == 100
      assert Enum.all?(results, fn {:ok, %Message{}} -> true; _ -> false end)

      stats = Manager.stats(queue_name)
      assert stats.pending == 100
    end

    test "handles concurrent dequeues without duplicates", %{queue_name: queue_name} do
      # Enqueue 50 messages
      1..50 |> Enum.each(fn i -> Manager.enqueue(queue_name, "msg_#{i}") end)

      # Dequeue concurrently
      tasks =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn ->
            Manager.dequeue(queue_name)
          end)
        end)

      results = Task.await_many(tasks)
      messages = Enum.reject(results, &is_nil/1)

      # All messages should be unique
      message_ids = Enum.map(messages, & &1.id)
      assert length(Enum.uniq(message_ids)) == length(message_ids)
      assert length(messages) == 50
    end
  end

  describe "edge cases" do
    test "handles empty payload", %{queue_name: queue_name} do
      {:ok, msg} = Manager.enqueue(queue_name, nil)
      assert msg.payload == nil
    end

    test "handles complex nested payload", %{queue_name: queue_name} do
      payload = %{
        user: %{id: 123, name: "John"},
        items: [%{id: 1, price: 10.50}, %{id: 2, price: 20.00}],
        metadata: %{timestamp: DateTime.utc_now()}
      }

      {:ok, msg} = Manager.enqueue(queue_name, payload)
      dequeued = Manager.dequeue(queue_name)
      assert dequeued.payload == payload
    end

    test "multiple queues operate independently" do
      queue1 = "queue_1_#{:erlang.unique_integer([:positive])}"
      queue2 = "queue_2_#{:erlang.unique_integer([:positive])}"

      {:ok, pid1} = Manager.start_link(queue_name: queue1)
      {:ok, pid2} = Manager.start_link(queue_name: queue2)

      on_exit(fn ->
        if Process.alive?(pid1), do: GenServer.stop(pid1)
        if Process.alive?(pid2), do: GenServer.stop(pid2)
      end)

      Manager.enqueue(queue1, "queue1_msg")
      Manager.enqueue(queue2, "queue2_msg")

      msg1 = Manager.dequeue(queue1)
      msg2 = Manager.dequeue(queue2)

      assert msg1.payload == "queue1_msg"
      assert msg2.payload == "queue2_msg"
      assert msg1.queue_name == queue1
      assert msg2.queue_name == queue2
    end
  end
end
