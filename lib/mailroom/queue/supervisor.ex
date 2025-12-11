defmodule Mailroom.Queue.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_queue(queue_name, opts \\ []) do
    child_spec = {Mailroom.Queue.Manager, [queue_name: queue_name] ++ opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def ensure_queue_started(queue_name, opts \\ []) do
    case start_queue(queue_name, opts) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def queue_exists?(queue_name) do
    case Registry.lookup(Mailroom.Queue.Registry, queue_name) do
      [{pid, _}] when is_pid(pid) -> true
      [] -> false
    end
  end

  def get_queue(queue_name) do
    case Registry.lookup(Mailroom.Queue.Registry, queue_name) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def list_queues do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_id, pid, _type, _modules} ->
      case Registry.keys(Mailroom.Queue.Registry, pid) do
        [queue_name] -> queue_name
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  def stop_queue(queue_name) do
    case get_queue(queue_name) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end
end
