defmodule Mailroom.Queue.Registry do
  def start_link() do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end
end
