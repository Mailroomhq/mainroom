defmodule Mailroom.Handlers.Demo do
  @moduledoc """
  Demo handler with configurable processing time for presentations.
  """
  require Logger

  def handle(payload) do
    # Get processing time from payload, default to 1 second
    process_time = Map.get(payload, "process_time_ms", 1000)
    task_name = Map.get(payload, "task", "demo task")

    Logger.info("🚀 Processing: #{task_name}")

    # Simulate work
    Process.sleep(process_time)

    Logger.info("✅ Completed: #{task_name}")

    :ok
  end
end
