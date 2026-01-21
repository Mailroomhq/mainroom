defmodule MailroomWeb.QueueLive.Index do
  use MailroomWeb, :live_view
  alias Mailroom.Queue.Supervisor
  alias Mailroom.Queue.StatsAggregator
  alias Mailroom.Producer.Client, as: Producer

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 p-8">
      <div class="max-w-6xl mx-auto">
        <!-- Header -->
        <div class="flex justify-between items-center mb-8">
          <h1 class="text-4xl font-bold text-gray-900">Mailroom Dashboard</h1>
          <div class="flex gap-2">
            <button
              phx-click="toggle_demo"
              class={"px-4 py-2 rounded-lg " <> if(@show_demo, do: "bg-purple-700 text-white", else: "bg-purple-600 text-white hover:bg-purple-700")}
            >
              Demo Mode
            </button>
            <button
              phx-click="toggle_form"
              class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
            >
              + New Queue
            </button>
          </div>
        </div>

        <!-- Demo Panel -->
        <%= if @show_demo do %>
          <div class="bg-gradient-to-r from-purple-600 to-indigo-600 rounded-lg shadow-lg p-6 mb-6 text-white">
            <h2 class="text-2xl font-bold mb-2">Demo Scenarios</h2>
            <p class="text-purple-100 mb-6">Click a scenario to see the queue system in action. Watch the stats update in real-time!</p>

            <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              <!-- Scenario 1: Basic Processing -->
              <button
                phx-click="demo_basic"
                class="bg-white/20 hover:bg-white/30 rounded-lg p-4 text-left transition-all"
              >
                <div class="text-lg font-semibold mb-1">Basic Processing</div>
                <div class="text-sm text-purple-100">Send 5 messages and watch them flow through the queue</div>
              </button>

              <!-- Scenario 2: Parallel Groups -->
              <button
                phx-click="demo_parallel_groups"
                class="bg-white/20 hover:bg-white/30 rounded-lg p-4 text-left transition-all"
              >
                <div class="text-lg font-semibold mb-1">Parallel Groups</div>
                <div class="text-sm text-purple-100">3 groups processing simultaneously - true parallelism!</div>
              </button>

              <!-- Scenario 3: Burst Load -->
              <button
                phx-click="demo_burst"
                class="bg-white/20 hover:bg-white/30 rounded-lg p-4 text-left transition-all"
              >
                <div class="text-lg font-semibold mb-1">Burst Load</div>
                <div class="text-sm text-purple-100">Send 12 messages across 4 groups, watch the queue handle the load</div>
              </button>

              <!-- Scenario 4: Group Ordering -->
              <button
                phx-click="demo_fifo"
                class="bg-white/20 hover:bg-white/30 rounded-lg p-4 text-left transition-all"
              >
                <div class="text-lg font-semibold mb-1">FIFO Ordering</div>
                <div class="text-sm text-purple-100">Messages in same group processed in order (check logs!)</div>
              </button>
            </div>

            <!-- Reset Button -->
            <div class="mt-6 pt-4 border-t border-white/20">
              <button
                phx-click="demo_reset"
                class="px-4 py-2 bg-red-500 hover:bg-red-600 rounded-lg text-sm font-medium transition-all"
              >
                Reset Demo (Clear All Queues)
              </button>
            </div>
          </div>
        <% end %>

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
                class="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <div class="text-6xl mb-4">📬</div>
              <p class="text-gray-500 text-lg">No queues yet.</p>
              <p class="text-gray-400 mt-2">Click "Demo Mode" above to see the system in action!</p>
            </div>
          <% else %>
            <%= for queue <- @queues do %>
              <div class="bg-white rounded-lg shadow p-6">
                <div class="flex justify-between items-center mb-4">
                  <!-- Queue Name -->
                  <h2 class="text-2xl font-semibold text-gray-800">{queue.name}</h2>

                  <div class="flex gap-2">
                    <!-- Send Message Button -->
                    <button
                      phx-click="toggle_message_form"
                      phx-value-queue-name={queue.name}
                      class="px-3 py-1 text-blue-600 border border-blue-600 rounded hover:bg-blue-50"
                    >
                      Send Message
                    </button>
                    <!-- Delete Button -->
                    <button
                      phx-click="delete_queue"
                      phx-value-queue-name={queue.name}
                      class="px-3 py-1 text-red-600 border border-red-600 rounded hover:bg-red-50"
                    >
                      Delete
                    </button>
                  </div>
                </div>

                <!-- Stats Grid -->
                <div class="grid grid-cols-4 gap-4">
                  <div class="text-center p-4 bg-blue-50 rounded-lg">
                    <div class="text-3xl font-bold text-blue-600">{queue.stats.pending}</div>
                    <div class="text-sm text-gray-600">Pending</div>
                  </div>
                  <div class="text-center p-4 bg-yellow-50 rounded-lg">
                    <div class="text-3xl font-bold text-yellow-600">{queue.stats.processing}</div>
                    <div class="text-sm text-gray-600">Processing</div>
                  </div>
                  <div class="text-center p-4 bg-green-50 rounded-lg">
                    <div class="text-3xl font-bold text-green-600">{queue.stats.completed}</div>
                    <div class="text-sm text-gray-600">Completed</div>
                  </div>
                  <div class="text-center p-4 bg-red-50 rounded-lg">
                    <div class="text-3xl font-bold text-red-600">{queue.stats.failed}</div>
                    <div class="text-sm text-gray-600">Failed</div>
                  </div>
                </div>

                <!-- Send Message Form -->
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

    subscribed =
      if connected?(socket) do
        Enum.each(queues, fn queue ->
          Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue.name}")
        end)

        # Start periodic refresh timer
        :timer.send_interval(250, self(), :refresh_stats)

        queues |> Enum.map(& &1.name) |> MapSet.new()
      else
        MapSet.new()
      end

    {:ok,
     assign(socket,
       queues: queues,
       show_form: false,
       show_demo: false,
       new_queue_name: "",
       message_form_queue: nil,
       message_payload: "",
       message_group_id: "",
       stats_dirty: false,
       subscribed: subscribed
     )}
  end

  # ====================
  # Demo Event Handlers
  # ====================

  @impl true
  def handle_event("toggle_demo", _params, socket) do
    {:noreply, update(socket, :show_demo, &not/1)}
  end

  @impl true
  def handle_event("demo_basic", _params, socket) do
    # Subscribe if not already subscribed
    socket = maybe_subscribe(socket, "demo")

    # Send first message to create the queue (synchronous - queue will be ready)
    Producer.publish(
      queue_name: "demo",
      payload: %{"task" => "Task #1", "process_time_ms" => 1000}
    )

    # Queue is now ready - refresh immediately
    queues = load_queues()

    # Send remaining messages in background
    Task.start(fn ->
      Enum.each(2..5, fn i ->
        Producer.publish(
          queue_name: "demo",
          payload: %{"task" => "Task ##{i}", "process_time_ms" => 1000}
        )
        Process.sleep(300)
      end)
    end)

    {:noreply,
     socket
     |> assign(queues: queues, stats_dirty: true)
     |> put_flash(:info, "Demo: Sending 5 messages...")}
  end

  @impl true
  def handle_event("demo_parallel_groups", _params, socket) do
    # Subscribe if not already subscribed
    socket = maybe_subscribe(socket, "demo")

    # Pre-create the queues (synchronous - queues will be ready)
    groups = ["alice", "bob", "charlie"]
    Enum.each(groups, fn group ->
      Producer.publish(
        queue_name: "demo",
        payload: %{"task" => "Setup #{group}", "process_time_ms" => 100},
        group_id: group
      )
    end)

    # Queues are now ready - refresh immediately
    queues = load_queues()

    # Now send the real messages in background
    Task.start(fn ->
      Enum.each(1..6, fn i ->
        group = Enum.at(groups, rem(i - 1, 3))
        Producer.publish(
          queue_name: "demo",
          payload: %{"task" => "#{group} - Job ##{div(i - 1, 3) + 1}", "process_time_ms" => 1500},
          group_id: group
        )
        Process.sleep(200)
      end)
    end)

    {:noreply,
     socket
     |> assign(queues: queues, stats_dirty: true)
     |> put_flash(:info, "Demo: 3 groups processing in parallel!")}
  end

  @impl true
  def handle_event("demo_burst", _params, socket) do
    # Subscribe if not already subscribed
    socket = maybe_subscribe(socket, "demo")

    # Pre-create the 4 groups (synchronous - queues will be ready)
    Enum.each(1..4, fn i ->
      Producer.publish(
        queue_name: "demo",
        payload: %{"task" => "Setup group #{i}", "process_time_ms" => 100},
        group_id: "group_#{i}"
      )
    end)

    # Queues are now ready - refresh immediately
    queues = load_queues()

    # Now send the burst in background (8 more messages, 12 total with setup)
    Task.start(fn ->
      Enum.each(1..8, fn i ->
        group = "group_#{rem(i - 1, 4) + 1}"
        Producer.publish(
          queue_name: "demo",
          payload: %{"task" => "Burst ##{i}", "process_time_ms" => 800},
          group_id: group
        )
        Process.sleep(100)
      end)
    end)

    {:noreply,
     socket
     |> assign(queues: queues, stats_dirty: true)
     |> put_flash(:info, "Demo: Burst of 12 messages across 4 groups!")}
  end

  @impl true
  def handle_event("demo_fifo", _params, socket) do
    # Subscribe if not already subscribed
    socket = maybe_subscribe(socket, "demo")

    # Pre-create the group (synchronous - queue will be ready)
    Producer.publish(
      queue_name: "demo",
      payload: %{"task" => "Setup ordered group", "process_time_ms" => 100},
      group_id: "ordered"
    )

    # Queue is now ready - refresh immediately
    queues = load_queues()

    # Send numbered messages to same group in background (4 more, 5 total with setup)
    Task.start(fn ->
      Enum.each(1..4, fn i ->
        Producer.publish(
          queue_name: "demo",
          payload: %{"task" => "Message ##{i} (check logs)", "process_time_ms" => 800},
          group_id: "ordered"
        )
        Process.sleep(100)
      end)
    end)

    {:noreply,
     socket
     |> assign(queues: queues, stats_dirty: true)
     |> put_flash(:info, "Demo: 5 ordered messages - check logs!")}
  end

  @impl true
  def handle_event("demo_reset", _params, socket) do
    # Unsubscribe from all queues
    Enum.each(socket.assigns.subscribed, fn queue_name ->
      Phoenix.PubSub.unsubscribe(Mailroom.PubSub, "queue:#{queue_name}")
    end)

    # Stop all queues
    Supervisor.list_queues()
    |> Enum.each(fn queue_name ->
      Supervisor.stop_queue(queue_name)
    end)

    # Clear stats and consumer tracking
    StatsAggregator.reset()
    Mailroom.Consumer.Manager.reset()

    {:noreply,
     socket
     |> assign(queues: [], subscribed: MapSet.new())
     |> put_flash(:info, "Demo reset complete. All queues cleared.")}
  end

  # ====================
  # Form Event Handlers
  # ====================

  @impl true
  def handle_event("toggle_form", _params, socket) do
    {:noreply, update(socket, :show_form, &not/1)}
  end

  @impl true
  def handle_event("toggle_message_form", %{"queue-name" => queue_name}, socket) do
    new_queue = if socket.assigns.message_form_queue == queue_name, do: nil, else: queue_name

    {:noreply, assign(socket, message_form_queue: new_queue, message_payload: "", message_group_id: "")}
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

    publish_opts =
      case group_id do
        "" -> [queue_name: queue_name, payload: payload]
        id -> [queue_name: queue_name, payload: payload, group_id: id]
      end

    {:ok, _message} = Producer.publish(publish_opts)

    {:noreply,
     socket
     |> assign(message_form_queue: nil, message_payload: "", message_group_id: "")
     |> put_flash(:info, "Message sent to #{queue_name}!")}
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
        StatsAggregator.register_queue(queue_name)

        queues = load_queues()

        socket = maybe_subscribe(socket, queue_name)

        {:noreply,
         socket
         |> assign(queues: queues, show_form: false, new_queue_name: "")
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

  # ====================
  # PubSub Handlers
  # ====================

  # Periodic refresh - only reload if stats are dirty
  @impl true
  def handle_info(:refresh_stats, socket) do
    if socket.assigns.stats_dirty do
      {:noreply, assign(socket, queues: load_queues(), stats_dirty: false)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({_source, event, queue_name}, socket)
      when event in [:stats_updated] or is_atom(event) do
    # Subscribe to parent queue if we aren't already
    socket = maybe_subscribe(socket, parent_queue_name(queue_name))

    # Mark stats as dirty - will be refreshed on next timer tick
    {:noreply, assign(socket, stats_dirty: true)}
  end

  # ====================
  # Private Functions
  # ====================

  defp maybe_subscribe(socket, queue_name) do
    if queue_name in socket.assigns.subscribed do
      socket
    else
      Phoenix.PubSub.subscribe(Mailroom.PubSub, "queue:#{queue_name}")
      assign(socket, subscribed: MapSet.put(socket.assigns.subscribed, queue_name))
    end
  end

  defp load_queues do
    parent_queues = StatsAggregator.list_parent_queues()

    Enum.map(parent_queues, fn queue_name ->
      stats = StatsAggregator.get_stats(queue_name)
      %{name: queue_name, stats: stats}
    end)
  end

  defp parent_queue_name(queue_name) do
    queue_name |> String.split(":", parts: 2) |> hd()
  end
end
