defmodule MailroomWeb.QueueController do
  use MailroomWeb, :controller

  alias Mailroom.Queue.Supervisor
  alias Mailroom.Queue.Manager

  def stats(conn, %{"queue_name" => queue_name}) do
    {:ok, _pid} = Supervisor.ensure_queue_started(queue_name)
    stats = Manager.stats(queue_name)

    conn
    |> json(%{
      queue_name: queue_name,
      pending: stats.pending,
      processing: stats.processing,
      completed: stats.completed,
      failed: stats.failed,
      total: stats.total
    })
  end
end
