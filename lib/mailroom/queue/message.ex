defmodule Mailroom.Queue.Message do
  @type status :: :pending | :processing | :completed | :failed
  @type t :: %__MODULE__{
          id: String.t(),
          payload: any(),
          queue_name: String.t(),
          status: status(),
          attempts: non_neg_integer(),
          max_attempts: pos_integer(),
          inserted_at: DateTime.t(),
          processing_started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          timeout_ms: pos_integer(),
          group_id: String.t() | nil
        }

  defstruct [
    :id,
    :payload,
    :queue_name,
    :status,
    :attempts,
    :max_attempts,
    :inserted_at,
    :processing_started_at,
    :completed_at,
    :timeout_ms,
    :group_id
  ]

  def new(queue_name, payload, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      payload: payload,
      queue_name: queue_name,
      status: :pending,
      attempts: 0,
      max_attempts: Keyword.get(opts, :max_attempts, 3),
      timeout_ms: Keyword.get(opts, :timeout_ms, 30_000),
      inserted_at: DateTime.utc_now(),
      processing_started_at: nil,
      completed_at: nil,
      group_id: Keyword.get(opts, :group_id)
    }
  end

  def mark_processing(message) do
    %{
      message
      | status: :processing,
        processing_started_at: DateTime.utc_now(),
        attempts: message.attempts + 1
    }
  end

  def mark_completed(message) do
    %{message | status: :completed, completed_at: DateTime.utc_now()}
  end

  def mark_failed(message) do
    if message.attempts >= message.max_attempts do
      %{message | status: :failed}
    else
      %{message | status: :pending, processing_started_at: nil}
    end
  end

  def timed_out?(%{status: :processing, processing_started_at: started_at, timeout_ms: timeout}) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    elapsed_ms > timeout
  end

  def timed_out?(_message), do: false

  def max_attempts_reached?(%{attempts: attempts, max_attempts: max_attempts}) do
    attempts >= max_attempts
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
