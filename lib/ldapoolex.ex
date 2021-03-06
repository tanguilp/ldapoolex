defmodule LDAPoolex do
  @doc """
  Calls `:eldap.add/3` using a worker of the `pool_name` pool
  """

  def add(pool_name, dn, attributes) do
    :poolboy.transaction(pool_name, fn worker ->
        Connection.call(worker, {:add, dn, attributes})
    end)
  end

  @doc """
  Calls `:eldap.modify/3` using a worker of the `pool_name` pool
  """

  def modify(pool_name, dn, modify_ops) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:modify, dn, modify_ops})
    end)
  end

  @doc """
  Calls `:eldap.modify_dn/5` using a worker of the `pool_name` pool
  """

  def modify_dn(pool_name, dn, new_rdn, delete_old_rdn, new_sup_dn) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:modify_password, dn, new_rdn, delete_old_rdn, new_sup_dn})
    end)
  end

  @doc """
  Calls `:eldap.modify_password/3` using a worker of the `pool_name` pool
  """

  def modify_password(pool_name, dn, new_password) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:modify_password, dn, new_password})
    end)
  end


  @doc """
  Calls `:eldap.modify_password/4` using a worker of the `pool_name` pool
  """

  def modify_password(pool_name, dn, new_password, old_password) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:modify_password, dn, new_password, old_password})
    end)
  end

  @doc """
  Calls `:eldap.search/2` using a worker of the `pool_name` pool
  """

  def search(pool_name, search_opts) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:search, search_opts})
    end)
  end

  @doc """
  Calls `:eldap.delete/2` using a worker of the `pool_name` pool
  """

  def delete(pool_name, dn) do
    :poolboy.transaction(pool_name, fn worker ->
      Connection.call(worker, {:delete, dn})
    end)
  end

  def child_spec(opts) do
    args = [
      name: case opts[:name] do
        {_, _} -> # already in Supervisor format
          opts[:name]

        _ ->
          {:local, opts[:name]}
      end,
      worker_module: LDAPoolex.ConnectionWorker,
      size: opts[:size] || 5,
      max_overflow: opts[:max_overflow] || 5
    ]

    :poolboy.child_spec(opts[:name], args, opts[:ldap_args])
  end

  @doc """
  Launches a supervised LDAP pool

  Options:
  - `:name`: the name of the pool (from poolboy). Defaults to `{:local, name}`
  - `:size`: the initial size of the pool (from poolboy). Defaults to `5`
  - `:max_overflow`: the number of *additional* LDAP connections that can be created under
  heavy load. Defaults to `5`, which means that by default the maximum number of connections
  is `10`
  - `:ldap_args`:
    - `:hosts`: the host list under. Note that this latter option must be a **list** of
    **charlists** (see examples below). No defaults
    - `:base`: the base DN to use for search. No default. Mandatory to load schema
    - `:load_schema`: `boolean()` that indicates whether the LDAP schema should be loaded.
    Defaults to `true`
    - `:bind_dn`: the DN to use to authenticate. If not set, the anonymous mode will be used
    instead
    - `:bind_password`: the password associated to the `:bind_dn`
    - `:connection_retry_delay`: connection retry delay when the LDAP connection is lost in
    milliseconds. Defaults to `3000`
    - `:ldap_open_opts`: will be passed as the second parameter of the `:eldap.open/2` function.
    Defaults to `[]`

  ## Example:
  ```elixir
  LDAPoolex.start_link(:slapd1, [ldap_args: [hosts: ['localhost'], base: 'dc=example,dc=org']])
  ```
  """
  def start_link(pool_name, opts) do
    children =
      if opts[:ldap_args][:load_schema] in [true, nil] do
        [
          child_spec(opts),
          {LDAPoolex.Schema, opts}
        ]
      else
        [
          child_spec(opts)
        ]
      end

    Supervisor.start_link(
      children,
      [strategy: :one_for_one, name: Module.concat(__MODULE__, pool_name)]
    )
  end
end
