defmodule Mailroom.Producer.ClientTest do
  use ExUnit.Case
  alias Mailroom.Producer.Client
  alias Mailroom.Queue.{Supervisor}

  setup do
    queue_name = "test_queue_#{:rand.uniform(100_000)}"
    {:ok, _pid} = Supervisor.ensure_queue_started(queue_name)

    {:ok, queue_name: queue_name}
  end

  test "publish/1 successfully publishes a message", %{queue_name: queue_name} do
    payload = %{to: "user@test.com", body: "single message"}

    {:ok, message} =
      Client.publish(
        queue_name: queue_name,
        payload: payload
      )

    assert message.payload == payload
  end

  test "publish/1 returns error when queue doesn't exist" do
    payload = %{to: "user@test.com", body: "single message"}

    {:error, message} =
      Client.publish(
        queue_name: "bad_queue_name",
        payload: payload
      )

    assert message == :queue_not_found
  end

  test "publish_batch/1 successfully publishes a message", %{queue_name: queue_name} do
    payloads = [
      %{to: "user1@test.com", body: "message 1"},
      %{to: "user2@test.com", body: "message 2"}
    ]

    {:ok, message} =
      Client.publish_batch(
        queue_name: queue_name,
        payloads: payloads
      )

    assert [msg1, msg2] = message
    assert msg1.payload == Enum.at(payloads, 0)
    assert msg2.payload == Enum.at(payloads, 1)
  end

  test "publish_batch/1 returns error when queue doesn't exist" do
    payloads = [
      %{to: "user1@test.com", body: "message 1"},
      %{to: "user2@test.com", body: "message 2"}
    ]

    {:error, message} =
      Client.publish_batch(
        queue_name: "bad_queue_name",
        payloads: payloads
      )

    assert message == :queue_not_found
  end
end
