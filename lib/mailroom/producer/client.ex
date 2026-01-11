defmodule Mailroom.Producer.Client do
  @moduledoc """
  Client for publishing message to queue
  """

  alias Mailroom.Queue.Router

  @doc """
  Publishes a message to a queue.

  ## Options
  - `:queue_name` (required) - Name of the queue
  - `:payload` (required) - The message payload
  - `:max_attempts` (optional) - Max retry attempts (default: 3)
  - `:timeout_ms` (optional) - Processing timeout in ms (default: 30000)
  - `:group_id` (optional) - Group messages together under this id

  ## Returns
  - `{:ok, message}` - Message published successfully

  ## Example
  Producer.Client.publish(
    queue_name: "emails",
    payload: %{to: "user@example.com", body: "Hello"},
    max_attempts: 5
  )
  """
  def publish(opts) do
    queue_name = Keyword.fetch!(opts, :queue_name)
    payload = Keyword.fetch!(opts, :payload)

    enqueue_opts = Keyword.take(opts, [:max_attempts, :timeout_ms, :group_id])
    {:ok, message} = Router.enqueue(queue_name, payload, enqueue_opts)

    {:ok, message}
  end

  @doc """
  Publishes multiple messages to a queue.

  ## Options
  - `:queue_name` (required) - Name of the queue
  - `:payloads` (required) - List of the message payloads
  - `:max_attempts` (optional) - Max retry attemps for all messages
  - `:timeout_ms` (optional) - Processing timeout for all messages
  - `:group_id` (optional) - Group messages together under this id

  ## Returns
  - `{:ok, messages}` - All messages published successfully

  ## Example
    Producer.Client.publish_batch(
      queue_name: "emails",
      payloads: [
        %{to: "user1@example.com", body: "Hello"},
        %{to: "user2@example.com", body: "Hi"},
      ],
      max_attempts: 5
    )
  """
  def publish_batch(opts) do
    queue_name = Keyword.fetch!(opts, :queue_name)
    payloads = Keyword.fetch!(opts, :payloads)

    enqueue_opts = Keyword.take(opts, [:max_attempts, :timeout_ms, :group_id])

    messages =
      Enum.map(payloads, fn payload ->
        {:ok, message} = Router.enqueue(queue_name, payload, enqueue_opts)
        message
      end)

    {:ok, messages}
  end
end
