defmodule MailroomWeb.QueueLive.Index do
  use MailroomWeb, :live_view
  alias Mailroom.Queue.Supervisor

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 p-8">
      <div class="max-w-6xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-8">
          <h1 class="text-4xl font-bold text-gray-900">Mailroom Dashboard</h1>
          <button
            phx-click="toggle_form"
            class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
          >
            + New Queue
          </button>
        </div>
        
    <!-- Create Queue Form -->
        <%= if @show_form do %>
          <div class="bg-white rounded-lg shadow p-6 mb-6">
            <h3 class="text-lg font-semibold mb-4">Create New Queue</h3>
            <form phx-submit="create_queue" class="flex gap-4">
              <input
                type="text"
                name="queue_name"
                value={@new_queue_name}
                phx-change="update_queue_name"
                placeholder="Enter queue name"
                class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-bl
    ue-500 focus:border-transparent"
                required
              />
              <button
                type="submit"
                class="px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700"
              >
                Create
              </button>
              <button
                type="button"
                phx-click="toggle_form"
                class="px-6 py-2 bg-gray-300 text-gray-700 rounded-lg hover:bg-gray-400"
              >
                Cancel
              </button>
            </form>
          </div>
        <% end %>
        
    <!-- Queue List -->
        <div class="space-y-4">
          <%= if @queues == [] do %>
            <div class="text-center py-12 bg-white rounded-lg shadow">
              <p class="text-gray-500 text-lg">No queues yet. Create your first queue!</p>
            </div>
          <% else %>
            <%= for queue <- @queues do %>
              <div class="bg-white rounded-lg shadow p-6">
                <div class="flex justify-between items-center">
                  <!-- Queue Name -->
                  <h2 class="text-2xl font-semibold text-gray-800">{queue.name}</h2>
                  
    <!-- Delete Button -->
                  <button
                    phx-click="delete_queue"
                    phx-value-queue-name={queue.name}
                    class="px-3 py-1 text-red-600 border border-red-600 rounded hover:bg-red-50"
                  >
                    Delete
                  </button>
                </div>
                
    <!-- Stats Grid -->
                <div class="grid grid-cols-4 gap-4 mt-4">
                  <div class="text-center">
                    <div class="text-3xl font-bold text-blue-600">{queue.stats.pending}</div>
                    <div class="text-sm text-gray-600">Pending</div>
                  </div>
                  <div class="text-center">
                    <div class="text-3xl font-bold text-yellow-600">{queue.stats.processing}</div>
                    <div class="text-sm text-gray-600">Processing</div>
                  </div>
                  <div class="text-center">
                    <div class="text-3xl font-bold text-green-600">{queue.stats.completed}</div>
                    <div class="text-sm text-gray-600">Completed</div>
                  </div>
                  <div class="text-center">
                    <div class="text-3xl font-bold text-red-600">{queue.stats.failed}</div>
                    <div class="text-sm text-gray-600">Failed</div>
                  </div>
                </div>
              </div>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    queues = load_queues()

    if connected?(socket) do
      Enum.each(queues, fn queue ->
        Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue.name}")
      end)
    end

    {:ok,
     socket
     |> assign(queues: queues)
     |> assign(show_form: false)
     |> assign(new_queue_name: "")}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("update_queue_name", %{"queue_name" => name}, socket) do
    {:noreply, assign(socket, new_queue_name: name)}
  end

  @impl true
  def handle_event("create_queue", _params, socket) do
    queue_name = socket.assigns.new_queue_name

    case Supervisor.start_queue(queue_name) do
      {:ok, _pid} ->
        queues = load_queues()

        Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue_name}")

        {:noreply,
         socket
         |> assign(queues: queues)
         |> assign(show_form: false)
         |> assign(new_queue_name: "")
         |> put_flash(:info, "Queue '#{queue_name}' created successfully!")}

      {:error, {:already_started, _pid}} ->
        {:noreply, put_flash(socket, :error, "Queue '#{queue_name}' already exists")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create queue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("delete_queue", %{"queue-name" => queue_name}, socket) do
    case Supervisor.stop_queue(queue_name) do
      :ok ->
        queues = load_queues()

        {:noreply,
         socket
         |> assign(queues: queues)
         |> put_flash(:info, "Queue '#{queue_name}' deleted successfully!")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Queue '#{queue_name}' not found")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delete queue: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({Mailroom.Queue.Manager, _event, _queue_name}, socket) do
    queues = load_queues()
    {:noreply, assign(socket, queues: queues)}
  end

  defp load_queues do
    queue_names = Supervisor.list_queues()

    Enum.map(queue_names, fn queue_name ->
      stats = Mailroom.Queue.Manager.stats(queue_name)
      %{name: queue_name, stats: stats}
    end)
  end
end
