defmodule LDAPoolex.PoolSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg)
  end

  def child_spec(args) do
    %{
      id: {__MODULE__, args[:name]},
      start: {__MODULE__, :start_link, [args]}
    }
  end

  @impl true
  def init(args) do
    children =
      if args[:load_schema] || true do
        [
          LDAPoolex.child_spec(args),
          {LDAPoolex.Schema, args}
        ]
      else
        [
          LDAPoolex.child_spec(args)
        ]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
