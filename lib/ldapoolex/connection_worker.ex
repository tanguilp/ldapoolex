defmodule LDAPoolex.ConnectionWorker do
  use Connection

  @behaviour :poolboy_worker

  require Logger

  @impl :poolboy_worker

  @doc """
  Launches an LDAP connection process and returns its pid
  """

  @spec start_link(Keyword.t()) ::
  {:ok, pid()}
  | {:error, {:already_started, pid()}}
  | {:error, term()}

  def start_link(args) do
    Connection.start_link(__MODULE__, args)
  end

  @doc """
  Calls `:eldap.add/3` where `conn` is the pid returned by `start_link/1`
  """

  def add(conn, dn, attributes), do: Connection.call(conn, {:add, dn, attributes})

  @doc """
  Calls `:eldap.modify/3` where `conn` is the pid returned by `start_link/1`
  """

  def modify(conn, dn, modify_ops), do: Connection.call(conn, {:modify, dn, modify_ops})

  @doc """
  Calls `:eldap.modify_dn/5` where `conn` is the pid returned by `start_link/1`
  """

  def modify_dn(conn, dn, new_rdn, delete_old_rdn, new_sup_dn), do: Connection.call(conn, {:modify_password, dn, new_rdn, delete_old_rdn, new_sup_dn})

  @doc """
  Calls `:eldap.modify_password/3` where `conn` is the pid returned by `start_link/1`
  """

  def modify_password(conn, dn, new_password), do: Connection.call(conn, {:modify_password, dn, new_password})

  @doc """
  Calls `:eldap.modify_password/4` where `conn` is the pid returned by `start_link/1`
  """

  def modify_password(conn, dn, new_password, old_password), do: Connection.call(conn, {:modify_password, dn, new_password, old_password})

  @doc """
  Calls `:eldap.search/2` where `conn` is the pid returned by `start_link/1`
  """

  def search(conn, search_opts), do: Connection.call(conn, {:search, search_opts})

  @doc """
  Calls `:eldap.delete/2` where `conn` is the pid returned by `start_link/1`
  """

  def delete(conn, dn), do: Connection.call(conn, {:delete, dn})

  def close(conn), do: Connection.call(conn, :close)

  @impl Connection

  def init(args) do
    state = %{
      hosts: args[:hosts],
      bind_dn: args[:bind_dn],
      bind_password: args[:bind_password],
      connection_retry_delay: args[:connection_retry_delay] || 3000,
      ldap_open_opts: args[:ldap_open_opts] || [],
      handle: nil
    }

    {:connect, :init, state}
  end

  @impl Connection

  def connect(info, %{hosts: hosts, ldap_open_opts: ldap_open_opts} = state) do
    Logger.info("LDAP #{inspect(info)} to #{inspect(hosts)} with options #{inspect(ldap_open_opts)}")

    case :eldap.open(hosts, ldap_open_opts) do
      {:ok, handle} ->
        state = %{state | handle: handle}

        case state[:bind_dn] do
          nil ->
            {:ok, state}

          _ ->
            case :eldap.simple_bind(handle, state[:bind_dn], state[:bind_password]) do
              :ok ->
                {:ok, state}

              {:error, reason} ->
                {:stop, {:eldap_simple_bind_error, reason}, state}
            end
        end

      {:error, reason} ->
        Logger.warn("Failed to connect to #{inspect hosts}: #{inspect(reason)}")

        {:backoff, state[:connection_retry_delay], state}
    end
  end

  @impl Connection

  def disconnect(_info, %{handle: handle} = state) do
    :ok = :eldap.close(handle)

    Logger.error("LDAP connection has been closed (state=#{inspect(state)}), reconnecting")

    {:connect, :reconnect, %{state | handle: nil}}
  end

  @impl Connection

  def handle_call(_, _, %{handle: nil} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call(:close, _, state) do
    {:stop, :close, :ok, state}
  end

  def handle_call({:add, dn, attributes}, _, %{handle: handle} = state) do
    handle
    |> :eldap.add(dn, attributes)
    |> handle_eldap_response(state)
  end

  def handle_call({:modify, dn, modify_ops}, _, %{handle: handle} = state) do
    handle
    |> :eldap.modify(dn, modify_ops)
    |> handle_eldap_response(state)
  end

  def handle_call({:modify_dn, dn, new_rdn, delete_old_rdn, new_sup_dn}, _, %{handle: handle} = state) do
    handle
    |> :eldap.modify_dn(dn, new_rdn, delete_old_rdn, new_sup_dn)
    |> handle_eldap_response(state)
  end

  def handle_call({:modify_password, dn, new_password}, _, %{handle: handle} = state) do
    case :eldap.modify_password(handle, dn, new_password) do
      {:ok, generated_password} ->
        {:reply, {:ok, {:password, generated_password}}}

      other ->
        handle_eldap_response(other, state)
    end
  end

  def handle_call({:modify_password, dn, new_password, old_password}, _, %{handle: handle} = state) do
    case :eldap.modify_password(handle, dn, new_password, old_password) do
      {:ok, generated_password} ->
        {:reply, {:ok, {:password, generated_password}}}

      other ->
        handle_eldap_response(other, state)
    end
  end

  def handle_call({:search, search_opts}, _, %{handle: handle} = state) do
    handle
    |> :eldap.search(search_opts)
    |> handle_eldap_response(state)
  end

  def handle_call({:delete, dn}, _, %{handle: handle} = state) do
    handle
    |> :eldap.delete(dn)
    |> handle_eldap_response(state)
  end

  defp handle_eldap_response(:ok, s), do: {:reply, :ok, s}
  defp handle_eldap_response({:ok, {:eldap_search_result, _, _} = res}, s), do: {:reply, res, s}
  defp handle_eldap_response({:ok, {:referral, referrals}}, s), do: {:reply, {:ok, referrals}, s}
  defp handle_eldap_response({:error, :ldap_closed} = e, s), do: {:disconnect, e, e, s}
  defp handle_eldap_response({:error, _} = e, s), do: {:reply, e, s}

  @impl Connection

  def terminate(reason, %{handle: handle} = state) when is_pid(handle) do
    Logger.error("Terminating LDAP connection (state=#{inspect(state)}) for reason: #{inspect(reason)}")
    :eldap.close(handle)
  end
end
