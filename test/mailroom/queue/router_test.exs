defmodule Mailroom.Queue.RouterTest do
  use ExUnit.Case, async(true)

  alias Mailroom.Queue.{Router, Message}

  setup do
    queue_name("test_queue_#{:erlang.unique_integer([:positive])}")
  end

  describe "enqueue/3" do
    test "enqueues a message and returns ok tuple", %{queue_name: queue_name} do
      payload = %{task: "send_email", to: "user@example.com"}
      assert {:ok, %Message{} = message} = Router.enqueue(queue_name, payload)
    end
  end
end
