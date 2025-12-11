defmodule MailroomWeb.MessageController do
  use MailroomWeb, :controller

  alias Mailroom.Queue.Supervisor
  alias Mailroom.Queue.Manager

  def publish(conn, %{"queue_name" => queue_name, "payload" => payload}) do
    with {:ok, _pid} <- Supervisor.ensure_queue_started(queue_name),
         {:ok, message} <- Manager.enqueue(queue_name, payload) do
      conn
      |> put_status(201)
      |> json(message_to_json(message))
    else
      {:error, _reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to publish message"})
    end
  end

  def consume(conn, %{"queue_name" => queue_name}) do
    {:ok, _pid} = Supervisor.ensure_queue_started(queue_name)

    case Manager.dequeue(queue_name) do
      nil ->
        send_resp(conn, 204, "")

      message ->
        conn
        |> json(message_to_json(message))
    end
  end

  def ack(conn, %{"queue_name" => queue_name, "id" => id}) do
    case Manager.ack(queue_name, id) do
      :ok ->
        conn
        |> json(%{success: true})

      {:error, :not_found} ->
        handle_queue_error(conn, :message_not_found)
    end
  rescue
    _e in [ArgumentError] ->
      handle_queue_error(conn, :queue_not_found)
  end

  def nack(conn, %{"queue_name" => queue_name, "id" => id}) do
    case Manager.nack(queue_name, id) do
      :ok ->
        conn
        |> json(%{success: true})

      {:error, :not_found} ->
        handle_queue_error(conn, :message_not_found)
    end
  rescue
    _e in [ArgumentError] ->
      handle_queue_error(conn, :queue_not_found)
  end

  defp handle_queue_error(conn, :queue_not_found) do
    conn
    |> put_status(404)
    |> json(%{error: "Queue not found"})
  end

  defp handle_queue_error(conn, :message_not_found) do
    conn
    |> put_status(404)
    |> json(%{error: "Message not found"})
  end

  defp handle_queue_error(conn, _reason) do
    conn
    |> put_status(500)
    |> json(%{error: "Internal server error"})
  end

  defp message_to_json(nil), do: nil

  defp message_to_json(message) do
    %{
      id: message.id,
      payload: message.payload,
      status: message.status,
      attempts: message.attempts,
      queue_name: message.queue_name
    }
  end
end
