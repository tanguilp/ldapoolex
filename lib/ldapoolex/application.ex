defmodule LDAPoolex.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      for {pool_name, args} <- Application.get_env(:ldapoolex, :pools, []) do
        args = Keyword.put(args, :name, pool_name)

        LDAPoolex.PoolSupervisor.child_spec(args)
      end

    opts = [strategy: :one_for_one, name: __MODULE__]

    Supervisor.start_link(children, opts)
  end
end
