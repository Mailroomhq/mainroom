defmodule MailroomWeb.QueueLive.Index do
  use MailroomWeb, :live_view
  alias Mailroom.Queue.Supervisor
  alias Mailroom.Queue.StatsAggregator

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
                <!-- Send Message Button -->
                <button
                  phx-click="toggle_message_form"
                  phx-value-queue-name={queue.name}
                  class="px-3 py-1 text-blue-600 border border-blue-600 rounded hover:bg-blue-50"
                >
                  Send Message
                </button>
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
                  <%= if @message_form_queue == queue.name do %>
                    <div class="mt-6 pt-6 border-t border-gray-200">
                      <h3 class="text-lg font-semibold mb-4">Send Message</h3>
                      <form phx-submit="send_message" class="space-y-4">
                        <div>
                          <label class="block text-sm font-medium text-gray-700 mb-2">
                            Payload (JSON or text)
                          </label>
                          <textarea
                            name="payload"
                            phx-change="update_message_payload"
                            placeholder='{"example": "data"}'
                            rows="4"
                            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                            required
                          ><%= @message_payload %></textarea>
                        </div>

                        <div>
                          <label class="block text-sm font-medium text-gray-700 mb-2">
                            Group ID (optional)
                          </label>
                          <input
                            type="text"
                            name="group_id"
                            value={@message_group_id}
                            phx-change="update_message_group_id"
                            placeholder="user_123"
                            class="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                          />
                        </div>

                        <input type="hidden" name="queue_name" value={queue.name} />
                        <div class="flex gap-4">
                          <button
                            type="submit"
                            class="px-6 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700"
                          >
                            Send
                          </button>
                          <button
                            type="button"
                            phx-click="toggle_message_form"
                            phx-value-queue-name={queue.name}
                            class="px-6 py-2 bg-gray-300 text-gray-700 rounded-lg hover:bg-gray-400"
                          >
                            Cancel
                          </button>
                        </div>
                      </form>
                    </div>
                  <% end %>
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
     |> assign(new_queue_name: "")
     |> assign(message_form_queue: nil)
     |> assign(message_payload: "")
     |> assign(message_group_id: "")}
  end

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, assign(socket, show_form: !socket.assigns.show_form)}
  end

  @impl true
  def handle_event("toggle_message_form", %{"queue-name" => queue_name}, socket) do
    new_queue = if socket.assigns.message_form_queue == queue_name, do: nil, else: queue_name

    {:noreply,
     socket
     |> assign(message_form_queue: new_queue)
     |> assign(message_payload: "")
     |> assign(message_group_id: "")}
  end

  @impl true
  def handle_event("update_message_payload", %{"payload" => payload}, socket) do
    {:noreply, assign(socket, message_payload: payload)}
  end

  @impl true
  def handle_event("update_message_group_id", %{"group_id" => group_id}, socket) do
    {:noreply, assign(socket, message_group_id: group_id)}
  end

  @impl true
  def handle_event("send_message", params, socket) do
    %{"queue_name" => queue_name, "payload" => payload_string, "group_id" => group_id} = params

    payload =
      case Jason.decode(payload_string) do
        {:ok, json} -> json
        {:error, _} -> payload_string
      end

    publish_opts = [queue_name: queue_name, payload: payload]

    publish_opts =
      if group_id != "", do: Keyword.put(publish_opts, :group_id, group_id), else: publish_opts

    case Mailroom.Producer.Client.publish(publish_opts) do
      {:ok, _message} ->
        {:noreply,
         socket
         |> assign(message_form_queue: nil)
         |> assign(message_payload: "")
         |> assign(message_group_id: "")
         |> put_flash(:info, "Message sent to #{queue_name}!")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to send message: #{inspect(reason)}")}
    end
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
        Mailroom.Queue.StatsAggregator.register_queue(queue_name)

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
  def handle_info({_source, event, queue_or_parent}, socket)
      when event in [:stats_updated] or is_atom(event) do
    parent =
      case String.split(queue_or_parent, ":", parts: 2) do
        [parent, _] -> parent
        [parent] -> parent
      end

    updated_queues =
      Enum.map(socket.assigns.queues, fn queue ->
        if queue.name == parent do
          %{queue | stats: StatsAggregator.get_stats(parent)}
        else
          queue
        end
      end)

    {:noreply, assign(socket, queues: updated_queues)}
  end

  def handle_info({Mailroom.Queue.Manager, _event, _queue_name}, socket) do
    queues = load_queues()
    {:noreply, assign(socket, queues: queues)}
  end

  defp load_queues do
    parent_queues = StatsAggregator.list_parent_queues()

    Enum.map(parent_queues, fn queue_name ->
      stats = Mailroom.Queue.StatsAggregator.get_stats(queue_name)
      %{name: queue_name, stats: stats}
    end)
  end
end
