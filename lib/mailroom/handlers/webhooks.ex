defmodule Mailroom.Handlers.Webhooks do
  require Logger

  def handle(payload) do
    Logger.info("Processing webhook: #{inspect(payload)}")

    Process.sleep(100)

    :ok
  end
end
