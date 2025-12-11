defmodule Mailroom.Queue.MessageTest do
  use ExUnit.Case, async: true

  alias Mailroom.Queue.Message

  describe "new/3" do
    test "creates a new message with default values" do
      message = Message.new("test_queue", %{data: "test"})

      assert message.queue_name == "test_queue"
      assert message.payload == %{data: "test"}
      assert message.status == :pending
      assert message.attempts == 0
      assert message.max_attempts == 3
      assert message.timeout_ms == 30_000
      assert message.inserted_at != nil
      assert message.processing_started_at == nil
      assert is_binary(message.id)
      assert byte_size(message.id) > 0
    end

    test "accepts custom max_attempts" do
      message = Message.new("test_queue", "payload", max_attempts: 5)
      assert message.max_attempts == 5
    end

    test "accepts custom timeout_ms" do
      message = Message.new("test_queue", "payload", timeout_ms: 60_000)
      assert message.timeout_ms == 60_000
    end

    test "generates unique IDs for different messages" do
      msg1 = Message.new("queue", "payload1")
      msg2 = Message.new("queue", "payload2")
      msg3 = Message.new("queue", "payload3")

      assert msg1.id != msg2.id
      assert msg2.id != msg3.id
      assert msg1.id != msg3.id
    end

    test "supports various payload types" do
      string_msg = Message.new("queue", "string payload")
      assert string_msg.payload == "string payload"

      map_msg = Message.new("queue", %{key: "value"})
      assert map_msg.payload == %{key: "value"}

      list_msg = Message.new("queue", [1, 2, 3])
      assert list_msg.payload == [1, 2, 3]

      nil_msg = Message.new("queue", nil)
      assert nil_msg.payload == nil
    end
  end

  describe "mark_processing/1" do
    test "transitions message from pending to processing" do
      message = Message.new("queue", "payload")
      assert message.status == :pending
      assert message.attempts == 0

      processing = Message.mark_processing(message)

      assert processing.status == :processing
      assert processing.attempts == 1
      assert processing.processing_started_at != nil
    end

    test "increments attempts on subsequent processing" do
      message = Message.new("queue", "payload")

      first_attempt = Message.mark_processing(message)
      assert first_attempt.attempts == 1

      # Simulate retry
      second_attempt =
        first_attempt
        |> Map.put(:status, :pending)
        |> Message.mark_processing()

      assert second_attempt.attempts == 2

      third_attempt =
        second_attempt
        |> Map.put(:status, :pending)
        |> Message.mark_processing()

      assert third_attempt.attempts == 3
    end

    test "sets processing_started_at timestamp" do
      message = Message.new("queue", "payload")
      processing = Message.mark_processing(message)

      assert %DateTime{} = processing.processing_started_at
      assert DateTime.compare(processing.processing_started_at, message.inserted_at) in [:gt, :eq]
    end
  end

  describe "mark_completed/1" do
    test "transitions message to completed status" do
      message =
        Message.new("queue", "payload")
        |> Message.mark_processing()

      completed = Message.mark_completed(message)

      assert completed.status == :completed
    end

    test "preserves message data" do
      original = Message.new("queue", %{important: "data"})
      processing = Message.mark_processing(original)
      completed = Message.mark_completed(processing)

      assert completed.id == original.id
      assert completed.payload == original.payload
      assert completed.queue_name == original.queue_name
      assert completed.attempts == 1
    end
  end

  describe "mark_failed/1" do
    test "transitions message to failed status" do
      message =
        Message.new("queue", "payload", max_attempts: 1)
        |> Message.mark_processing()

      failed = Message.mark_failed(message)

      assert failed.status == :failed
    end

    test "returns to pending if max_attempts not reached" do
      message =
        Message.new("queue", "payload", max_attempts: 3)
        |> Message.mark_processing()

      # First failure (attempt 1 of 3)
      retry = Message.mark_failed(message)
      assert retry.status == :pending
      assert retry.attempts == 1

      # Second failure (attempt 2 of 3)
      retry2 =
        retry
        |> Message.mark_processing()
        |> Message.mark_failed()

      assert retry2.status == :pending
      assert retry2.attempts == 2
    end

    test "marks as failed when max_attempts reached" do
      message = Message.new("queue", "payload", max_attempts: 2)

      # Attempt 1
      attempt1 = Message.mark_processing(message)
      assert attempt1.attempts == 1

      # Fail attempt 1
      retry = Message.mark_failed(attempt1)
      assert retry.status == :pending

      # Attempt 2
      attempt2 = Message.mark_processing(retry)
      assert attempt2.attempts == 2

      # Fail attempt 2 - should now be permanently failed
      failed = Message.mark_failed(attempt2)
      assert failed.status == :failed
      assert failed.attempts == 2
    end
  end

  describe "timed_out?/1" do
    test "returns false for pending messages" do
      message = Message.new("queue", "payload")
      assert Message.timed_out?(message) == false
    end

    test "returns false for processing messages within timeout" do
      message =
        Message.new("queue", "payload", timeout_ms: 5000)
        |> Message.mark_processing()

      assert Message.timed_out?(message) == false
    end

    test "returns true for processing messages past timeout" do
      message =
        Message.new("queue", "payload", timeout_ms: 100)
        |> Message.mark_processing()

      # Wait for timeout
      Process.sleep(150)

      assert Message.timed_out?(message) == true
    end

    test "handles messages with different timeout values" do
      short_timeout =
        Message.new("queue", "payload", timeout_ms: 50)
        |> Message.mark_processing()

      long_timeout =
        Message.new("queue", "payload", timeout_ms: 10_000)
        |> Message.mark_processing()

      Process.sleep(100)

      assert Message.timed_out?(short_timeout) == true
      assert Message.timed_out?(long_timeout) == false
    end

    test "returns false for completed messages" do
      message =
        Message.new("queue", "payload")
        |> Message.mark_processing()
        |> Message.mark_completed()

      assert Message.timed_out?(message) == false
    end

    test "returns false for failed messages" do
      message =
        Message.new("queue", "payload", max_attempts: 1)
        |> Message.mark_processing()
        |> Message.mark_failed()

      assert Message.timed_out?(message) == false
    end
  end

  describe "max_attempts_reached?/1" do
    test "returns false when attempts below max" do
      message = Message.new("queue", "payload", max_attempts: 3)
      assert Message.max_attempts_reached?(message) == false

      processing = Message.mark_processing(message)
      assert processing.attempts == 1
      assert Message.max_attempts_reached?(processing) == false
    end

    test "returns true when attempts equal max" do
      message = Message.new("queue", "payload", max_attempts: 2)

      attempt1 = Message.mark_processing(message)
      assert attempt1.attempts == 1
      assert Message.max_attempts_reached?(attempt1) == false

      attempt2 =
        attempt1
        |> Map.put(:status, :pending)
        |> Message.mark_processing()

      assert attempt2.attempts == 2
      assert Message.max_attempts_reached?(attempt2) == true
    end

    test "returns true when attempts exceed max" do
      message = Message.new("queue", "payload", max_attempts: 1)
      processing = Message.mark_processing(message)

      # Artificially set attempts above max (shouldn't happen in practice)
      over_max = %{processing | attempts: 5}
      assert Message.max_attempts_reached?(over_max) == true
    end
  end

  describe "message lifecycle integration" do
    test "successful message flow: pending -> processing -> completed" do
      message = Message.new("queue", "payload")
      assert message.status == :pending
      assert message.attempts == 0

      processing = Message.mark_processing(message)
      assert processing.status == :processing
      assert processing.attempts == 1

      completed = Message.mark_completed(processing)
      assert completed.status == :completed
      assert completed.attempts == 1
    end

    test "retry flow: pending -> processing -> pending -> processing -> completed" do
      message = Message.new("queue", "payload", max_attempts: 3)

      # First attempt fails
      attempt1 = Message.mark_processing(message)
      assert attempt1.attempts == 1

      retry1 = Message.mark_failed(attempt1)
      assert retry1.status == :pending
      assert retry1.attempts == 1

      # Second attempt succeeds
      attempt2 = Message.mark_processing(retry1)
      assert attempt2.attempts == 2

      completed = Message.mark_completed(attempt2)
      assert completed.status == :completed
      assert completed.attempts == 2
    end

    test "permanent failure flow: pending -> processing -> ... -> failed" do
      message = Message.new("queue", "payload", max_attempts: 3)

      # Attempt 1
      attempt1 = Message.mark_processing(message)
      retry1 = Message.mark_failed(attempt1)
      assert retry1.status == :pending

      # Attempt 2
      attempt2 = Message.mark_processing(retry1)
      retry2 = Message.mark_failed(attempt2)
      assert retry2.status == :pending

      # Attempt 3 - final attempt
      attempt3 = Message.mark_processing(retry2)
      failed = Message.mark_failed(attempt3)

      assert failed.status == :failed
      assert failed.attempts == 3
      assert Message.max_attempts_reached?(failed) == true
    end

    test "timeout detection during processing" do
      message = Message.new("queue", "payload", timeout_ms: 100)
      processing = Message.mark_processing(message)

      assert Message.timed_out?(processing) == false

      Process.sleep(150)

      assert Message.timed_out?(processing) == true
    end
  end
end
