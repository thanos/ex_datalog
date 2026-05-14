defmodule ExDatalog.Storage.ETS do
  @moduledoc """
  ETS-based storage implementation using per-relation tables.

  This backend stores facts in ETS tables (one per relation), providing
  off-heap storage that reduces GC pressure for large fact sets (>100K tuples)
  and enables concurrent read access.

  ## Key design: wrapped tuples

  ETS `:set` tables use the first element of a tuple as the key. For Datalog
  facts like `{:alice, :bob}` and `{:alice, :carol}`, the key `:alice` would
  collide — the second would overwrite the first. To avoid this, the ETS backend
  wraps every fact tuple in a 1-element tuple: `{{:alice, :bob}}`. The wrapped
  tuple's sole element — the entire original tuple — becomes the ETS key,
  guaranteeing set semantics matching `Storage.Map`.

  ## Trade-offs vs Storage.Map

  - **Memory:** Data lives off-heap, avoiding costly copying of large fact sets
    during the semi-naive fixpoint loop.
  - **Read performance:** `:ets.member/2` and `:ets.info/2` are O(1) for size.
    Concurrent reads are supported via `:read_concurrency` when configured.
  - **Write performance:** `:ets.insert/2` is O(1) for `:set` tables.
  - **Iteration:** `stream/2` returns a deterministically sorted list via
    `Enum.sort(:ets.tab2list(table))`, ensuring consistent output across runs.
  - **Lifecycle:** ETS tables are owned by the creating process. Call
    `teardown/1` to delete all tables when evaluation completes.

  ## Determinism

  ETS table iteration order is not guaranteed. This backend normalizes output
  by sorting the result of `stream/2` and `relations/1`, ensuring identical
  programs produce identical results regardless of backend choice.

  ## Options

  The `init/2` function accepts an optional keyword list:

  - `:access` — ETS access mode, `:private` (default) or `:public`.
    `:public` enables `:read_concurrency` for concurrent read workloads.
  """

  @behaviour ExDatalog.Storage

  alias ExDatalog.Capabilities

  @type table_ref :: :ets.table()
  @type t :: %__MODULE__{
          tables: %{ExDatalog.Storage.relation_name() => table_ref()},
          schemas: ExDatalog.Storage.schemas(),
          indexes: %{
            {ExDatalog.Storage.relation_name(), ExDatalog.Storage.index_key()} => table_ref()
          },
          options: keyword()
        }

  defstruct tables: %{}, schemas: %{}, indexes: %{}, options: []

  @doc """
  Initializes ETS storage for the given relation schemas.

  Creates one ETS table per relation with `:set` type and wrapped-tuple keys
  for correct multi-arity fact storage. Tables are created with the configured
  access mode (default: `:private`).

  ## Options

  - `:access` — `:private` (default) or `:public`. When `:public`,
    `:read_concurrency` is enabled for concurrent read workloads.
  - `:write_concurrency` — `boolean` (default: `false`). When `true`,
    `:write_concurrency` is enabled on each ETS table.
  """
  @impl ExDatalog.Storage
  @spec init(ExDatalog.Storage.schemas()) :: t()
  def init(schemas), do: init(schemas, [])

  @spec init(ExDatalog.Storage.schemas(), keyword()) :: t()
  def init(schemas, opts) do
    access = Keyword.get(opts, :access, :private)
    write_concurrency = Keyword.get(opts, :write_concurrency, false)
    read_concurrency = Keyword.get(opts, :read_concurrency, access == :public)

    options = [
      access: access,
      write_concurrency: write_concurrency,
      read_concurrency: read_concurrency
    ]

    tables =
      schemas
      |> Map.keys()
      |> Map.new(fn name ->
        table_opts = [
          :set,
          access,
          read_concurrency: read_concurrency,
          write_concurrency: write_concurrency
        ]

        ref = :ets.new(:ex_datalog_ets, table_opts)
        {name, ref}
      end)

    %__MODULE__{tables: tables, schemas: schemas, indexes: %{}, options: options}
  end

  @doc """
  Inserts a single tuple into a relation.

  The tuple is wrapped as `{tuple}` before insertion so the entire tuple
  becomes the ETS key. Idempotent: inserting a tuple that already exists
  is a no-op (`:set` semantics with whole-tuple key).

  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec insert(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.tuple_values()) :: t()
  def insert(%__MODULE__{tables: tables} = state, relation, tuple) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} ->
        :ets.insert(ref, {tuple})
        state

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc """
  Inserts an enumerable of tuples into a relation.

  More efficient than repeated `insert/3` calls for bulk loading.
  Idempotent for individual tuples.

  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec insert_many(t(), ExDatalog.Storage.relation_name(), Enumerable.t()) :: t()
  def insert_many(%__MODULE__{tables: tables} = state, relation, tuples) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} ->
        Enum.each(tuples, fn tuple -> :ets.insert(ref, {tuple}) end)
        state

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc """
  Checks whether a tuple exists in a relation.

  Uses `:ets.member/2` for O(1) lookup by the wrapped tuple key.
  Returns `true` if the exact tuple is present, `false` otherwise.
  Returns `false` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec member?(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.tuple_values()) ::
          boolean()
  def member?(%__MODULE__{tables: tables} = state, relation, tuple) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} -> :ets.member(ref, tuple)
      :error -> false
    end
  end

  @doc """
  Returns the number of tuples stored in a relation.

  Returns `0` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec size(t(), ExDatalog.Storage.relation_name()) :: non_neg_integer()
  def size(%__MODULE__{tables: tables} = state, relation) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} -> :ets.info(ref, :size)
      :error -> 0
    end
  end

  @doc """
  Returns all tuples in a relation as a deterministically sorted list.

  Unwraps the stored `{tuple}` entries back to plain tuples and sorts
  them via `Enum.sort/1` to guarantee deterministic iteration order.
  Returns `[]` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec stream(t(), ExDatalog.Storage.relation_name()) :: Enumerable.t()
  def stream(%__MODULE__{tables: tables} = state, relation) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} ->
        ref
        |> :ets.tab2list()
        |> Enum.map(fn {tuple} -> tuple end)
        |> Enum.sort()

      :error ->
        []
    end
  end

  @doc """
  Retrieves tuples matching an indexed key.

  Returns tuples from a pre-built index that match the given `key` on the
  specified `columns`. Returns `[]` if the index or key does not exist.

  Must call `build_index/3` before calling `get_indexed/4` for the same
  relation and columns. Results are sorted for deterministic ordering.
  """
  @impl ExDatalog.Storage
  @spec get_indexed(
          t(),
          ExDatalog.Storage.relation_name(),
          ExDatalog.Storage.index_key(),
          ExDatalog.Storage.key_values()
        ) ::
          Enumerable.t()
  def get_indexed(%__MODULE__{indexes: indexes} = state, relation, columns, key) do
    guard_not_tombstoned!(state)

    case Map.fetch(indexes, {relation, columns}) do
      {:ok, index_ref} ->
        case :ets.lookup(index_ref, key) do
          [{^key, tuples_set}] -> tuples_set |> MapSet.to_list() |> Enum.sort()
          [] -> []
        end

      :error ->
        []
    end
  end

  @doc """
  Builds a hash index on the specified columns for a relation.

  Creates a new ETS table mapping projected column values to lists of tuples.
  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec build_index(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.index_key()) :: t()
  def build_index(%__MODULE__{tables: tables, indexes: indexes} = state, relation, columns) do
    guard_not_tombstoned!(state)

    case Map.fetch(tables, relation) do
      {:ok, ref} ->
        index_data = build_index_from_table(ref, columns)
        index_ref = :ets.new(:ex_datalog_index, [:set, :private])

        Enum.each(index_data, fn {key, tuples_set} ->
          :ets.insert(index_ref, {key, tuples_set})
        end)

        %{state | indexes: Map.put(indexes, {relation, columns}, index_ref)}

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc """
  Incrementally merges delta tuples into an existing index.

  If no index exists for the given relation and columns, one is built from
  the current relation data first, then the delta is merged in.

  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec update_index(
          t(),
          ExDatalog.Storage.relation_name(),
          ExDatalog.Storage.index_key(),
          Enumerable.t()
        ) :: t()
  def update_index(
        %__MODULE__{tables: tables, indexes: indexes} = state,
        relation,
        columns,
        delta
      ) do
    guard_not_tombstoned!(state)
    key = {relation, columns}

    {index_ref, updated_indexes} =
      case Map.fetch(indexes, key) do
        {:ok, ref} ->
          {ref, indexes}

        :error ->
          build_or_raise_index(tables, indexes, key, relation, columns)
      end

    merge_delta_into_index(index_ref, delta, columns)
    %{state | indexes: updated_indexes}
  end

  @doc """
  Returns a sorted list of all relation names in the storage.
  """
  @impl ExDatalog.Storage
  @spec relations(t()) :: [ExDatalog.Storage.relation_name()]
  def relations(%__MODULE__{schemas: schemas}) do
    schemas |> Map.keys() |> Enum.sort()
  end

  @doc """
  Returns the capabilities of this storage backend.

  The ETS backend supports arithmetic and comparison constraints, provenance,
  and indexed lookup. `concurrent_reads` reflects the configured access mode.
  """
  @impl ExDatalog.Storage
  @spec capabilities(t()) :: Capabilities.t()
  def capabilities(%__MODULE__{options: options}) do
    access = Keyword.get(options, :access, :private)
    concurrent_reads = access == :public

    %Capabilities{
      storage_type: :ets,
      indexed_lookup: true,
      concurrent_reads: concurrent_reads,
      arithmetic_constraints: true,
      comparison_constraints: true,
      type_predicates: true,
      string_predicates: true,
      provenance: true,
      external_execution: false
    }
  end

  @doc """
  Deletes all ETS tables owned by this storage backend.

  Must be called when evaluation completes to release ETS table resources.
  After `teardown/1`, the state is tombstoned — subsequent operations will
  raise `ArgumentError` with a clear message rather than crashing with
  opaque `:badarg` from the deleted ETS tables.

  This function is idempotent — calling it twice does not raise an error.
  """
  @impl ExDatalog.Storage
  @spec teardown(t()) :: :ok
  def teardown(%__MODULE__{tables: tables, indexes: indexes}) do
    Enum.each(tables, fn {_name, ref} ->
      if :ets.info(ref, :name) != :undefined, do: :ets.delete(ref)
    end)

    Enum.each(indexes, fn {_key, ref} ->
      if :ets.info(ref, :name) != :undefined, do: :ets.delete(ref)
    end)

    :ok
  end

  defp merge_delta_into_index(index_ref, delta, columns) do
    Enum.each(delta, fn tuple ->
      k = project_tuple(tuple, columns)
      upsert_index_entry(index_ref, k, tuple)
    end)
  end

  defp upsert_index_entry(index_ref, key, tuple) do
    case :ets.lookup(index_ref, key) do
      [{^key, existing_set}] ->
        unless MapSet.member?(existing_set, tuple) do
          :ets.insert(index_ref, {key, MapSet.put(existing_set, tuple)})
        end

      [] ->
        :ets.insert(index_ref, {key, MapSet.new([tuple])})
    end
  end

  defp build_index_from_table(ref, columns) do
    ref
    |> :ets.tab2list()
    |> Enum.map(fn {tuple} -> tuple end)
    |> Enum.group_by(&project_tuple(&1, columns))
    |> Map.new(fn {k, tuples} -> {k, MapSet.new(tuples)} end)
  end

  defp project_tuple(tuple, columns) do
    columns
    |> Enum.map(&elem(tuple, &1))
    |> List.to_tuple()
  end

  defp guard_not_tombstoned!(%__MODULE__{tables: tables}) do
    case Map.values(tables) do
      [] ->
        raise ArgumentError, "ETS storage has no tables — not initialized or already torn down"

      [ref | _] ->
        if :ets.info(ref, :name) == :undefined do
          raise ArgumentError, "ETS storage has been torn down and cannot be used"
        end

        :ok
    end
  end

  defp build_or_raise_index(tables, indexes, key, relation, columns) do
    case Map.fetch(tables, relation) do
      {:ok, ref} ->
        index_data = build_index_from_table(ref, columns)
        new_ref = :ets.new(:ex_datalog_index, [:set, :private])
        Enum.each(index_data, fn {k, tuples} -> :ets.insert(new_ref, {k, tuples}) end)
        {new_ref, Map.put(indexes, key, new_ref)}

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end
end
