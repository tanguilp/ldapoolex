defmodule LDAPoolex.Schema do
  use GenServer

  require Logger

  def start_link(args) do
    GenServer.start_link(__MODULE__,
                         args,
                         name: String.to_atom(Atom.to_string(args[:name]) <> "_schema_loader"))
  end

  @impl GenServer

  def init(args) do
    table_name = table_name(args[:name])

    :ets.new(table_name, [:named_table, :set, :protected, {:read_concurrency, true}])

    state = Keyword.put(args, :table, table_name)

    {:ok, state, {:continue, :load_schema}}
  end

  @doc """
  Returns the schema information of an attribute

  Takes into parameter the pool name (an `atom()`) and the attribute name (a `String.t()`)
  and returns the associated schema data, or `nil` if the attribute doesn't exist in the
  schema.

  ## Example
  ```elixir
  iex> LDAPoolex.SchemaLoader.get(:poule_do, "cn")
  %{
    equality: "caseIgnoreMatch",
    name: "cn",
    ordering: nil,
    single_valued: false,
    syntax: "1.3.6.1.4.1.1466.115.121.1.15{32768}"
  }
  iex> LDAPoolex.SchemaLoader.get(:poule_do, "createTimestamp")
  %{
    equality: "generalizedTimeMatch",
    name: "createTimestamp",
    ordering: "generalizedTimeOrderingMatch",
    single_valued: true,
    syntax: "1.3.6.1.4.1.1466.115.121.1.24"
  }
  iex> LDAPoolex.SchemaLoader.get(:poule_do, "uid")
  %{
    equality: "caseIgnoreMatch",
    name: "uid",
    ordering: nil,
    single_valued: false,
    syntax: "1.3.6.1.4.1.1466.115.121.1.15{256}"
  }
  ```
  """

  @spec get(atom(), String.t())
  :: %{
    name: String.t(),
    syntax: String.t(),
    single_valued: boolean(),
    equality: String.t() | nil,
    ordering: String.t() | nil
  } | nil

  def get(pool_name, attribute) do
    [{_attribute, syntax, single_valued, equality, ordering}] =
      pool_name
      |> table_name()
      |> :ets.lookup(attribute)

    %{
      name: attribute,
      syntax: to_str(syntax),
      single_valued: single_valued,
      equality: to_str(equality),
      ordering: to_str(ordering)
    }
  rescue
    _ ->
      nil
  end

  defp table_name(pool_name) do
    String.to_atom("LDAPoolex_" <>Atom.to_string(pool_name) <> "_schema")
  end

  defp to_str(nil), do: nil
  defp to_str(charlist), do: to_string(charlist)

  @impl GenServer

  def handle_continue(:load_schema, state) do
    load_schema(state)

    {:noreply, state}
  end

  @impl GenServer

  def handle_call(:load_schema, _from, state) do
    load_schema(state)

    {:reply, :ok, state}
  end

  @impl GenServer

  def handle_info(:load_schema, state) do
    load_schema(state)

    {:noreply, state}
  end

  defp load_schema(state) do
    get_subschema_subentry_dn(state)
    |> get_matching_rule_use(state)
    |> save_attribute_types_to_table(state)
  rescue
    e ->
      Logger.warn("Error while loading schema for pool `#{state[:name]}` (#{Exception.message(e)})")

      Process.send_after(self(), :load_schema, state[:connection_retry_delay] || 3000)
  end

  defp get_subschema_subentry_dn(state) do
    {:eldap_search_result,
      [
        {:eldap_entry, _root_dse,
          [{'subschemaSubentry', [subschema_subentry_dn]}]}
      ], []
    } =
      LDAPoolex.search(state[:name],
                       [
                         base: state[:ldap_args][:base],
                         filter: :eldap.present('objectClass'),
                         attributes: ['subschemaSubentry'],
                         scope: :eldap.baseObject()]
      )

    subschema_subentry_dn
  end

  defp get_matching_rule_use(subschema_subentry_dn, state) do
    {:eldap_search_result,
      [
        {:eldap_entry, _root_dse,
          [{_dn, attribute_types}]}
      ], []
    } =
      LDAPoolex.search(state[:name],
                       [
                         base: subschema_subentry_dn,
                         filter: :eldap.equalityMatch('objectClass', 'subschema'),
                         scope: :eldap.baseObject(),
                         attributes: ['attributeTypes']
                       ]
      )

    attribute_types
  end

  defp save_attribute_types_to_table(attribute_types, state) do
    attribute_type_list =
      Enum.into(
        attribute_types,
        [],
        fn
          attribute_type ->
            # we just add the prefix to make it work with the parser
            'attributetype ' ++ attribute_type
            |> :schema_lexer.string()
            |> elem(1)
            |> :schema_parser.parse()
            |> case do
              {:ok, [{:attribute_type, key_values}]} ->
                Enum.into(key_values, %{}, fn {key, value} -> {key, value} end)

              error ->
               raise error
            end
        end
      )

    object_list = Enum.map(
      attribute_type_list,
      fn
        %{syntax: _} = entry ->
          {
            List.first(entry[:name]),
            elem(entry[:syntax], 2),
            entry[:single_value] || false,
            case entry[:equality] do
              {_, _, val} ->
                val

              _ ->
                nil
            end,
            case entry[:ordering] do
              {_, _, val} ->
                val

              _ ->
                nil
            end
          }

        %{sup: _} = entry ->
          sup_entry = get_root_sup_entry(entry, attribute_type_list)

          {
            List.first(entry[:name]),
            elem(sup_entry[:syntax], 2),
            sup_entry[:single_value] || false,
            case sup_entry[:equality] do
              {_, _, val} ->
                val

              _ ->
                nil
            end,
            case sup_entry[:ordering] do
              {_, _, val} ->
                val

              _ ->
                nil
            end
          }
      end
    )

    :ets.delete_all_objects(state[:table])
    :ets.insert(state[:table], object_list)
  end

  defp get_root_sup_entry(entry, entry_list) do
    case Enum.find(entry_list, fn m -> m[:name] == entry[:sup] end) do
      %{sup: _} = sup_entry ->
        get_root_sup_entry(sup_entry, entry_list)

      sup_entry ->
        sup_entry
    end
  end
end
