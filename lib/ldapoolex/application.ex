defmodule LDAPoolex.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      for {pool_name, opts} <- Application.get_env(:ldapoolex, :pools, []) do
        LDAPoolex.child_spec(pool_name, opts)
      end

    opts = [strategy: :one_for_one, name: __MODULE__]

    Supervisor.start_link(children, opts)
  end
end
