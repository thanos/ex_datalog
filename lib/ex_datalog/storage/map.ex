defmodule ExDatalog.Storage.Map do
  @moduledoc """
  Map-based storage implementation using Maps and MapSets.

  This is the default storage backend. It uses immutable Elixir data structures
  (Maps and MapSets) which are thread-safe and easy to inspect, but may suffer
  GC pressure for very large fact sets (>100K tuples). An ETS-based
  implementation (`Storage.ETS`) is planned for Phase 8.

  ## Internal structure

      %{
        relations: %{
          "parent" => MapSet.new([{:alice, :bob}, {:carol, :dave}]),
          ...
        },
        indexes: %{
          {"parent", [1]} => %{
            {:bob} => MapSet.new([{:alice, :bob}]),
            {:dave} => MapSet.new([{:carol, :dave}])
          }
        },
        schemas: %{
          "parent" => %{arity: 2, types: [:atom, :atom]},
          ...
        }
      }

  Index keys are always tuples, even for single-column indexes. This avoids
  ambiguity between a plain value and a 1-tuple.
  """

  @behaviour ExDatalog.Storage

  @type index :: %{ExDatalog.Storage.key_values() => MapSet.t()}
  @type t :: %__MODULE__{
          relations: %{ExDatalog.Storage.relation_name() => MapSet.t()},
          indexes: %{
            {ExDatalog.Storage.relation_name(), ExDatalog.Storage.index_key()} => index()
          },
          schemas: ExDatalog.Storage.schemas()
        }

  defstruct relations: %{}, indexes: %{}, schemas: %{}

  @doc """
  Initializes storage for the given relation schemas.

  `schemas` is a map from relation name to `%{arity: n, types: [atom()]}`.
  Creates an empty `MapSet` for each relation and returns the initial state.

  Raises if two schemas share the same relation name (should be caught by
  validation before reaching storage).
  """
  @impl ExDatalog.Storage
  @spec init(ExDatalog.Storage.schemas()) :: t()
  def init(schemas) do
    relations =
      schemas
      |> Map.keys()
      |> Map.new(fn name -> {name, MapSet.new()} end)

    %__MODULE__{relations: relations, indexes: %{}, schemas: schemas}
  end

  @doc """
  Inserts a single tuple into a relation.

  Idempotent: inserting a tuple that already exists is a no-op (MapSet semantics).
  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec insert(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.tuple_values()) :: t()
  def insert(%__MODULE__{relations: rels} = state, relation, tuple) do
    case Map.fetch(rels, relation) do
      {:ok, set} ->
        %{state | relations: Map.put(rels, relation, MapSet.put(set, tuple))}

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc """
  Inserts an enumerable of tuples into a relation.

  More efficient than repeated `insert/3` calls for bulk loading, as it
  reduces Map updates. Idempotent for individual tuples.
  Raises `ArgumentError` if `relation` is not in the schema.
  """
  @impl ExDatalog.Storage
  @spec insert_many(t(), ExDatalog.Storage.relation_name(), Enumerable.t()) :: t()
  def insert_many(%__MODULE__{relations: rels} = state, relation, tuples) do
    case Map.fetch(rels, relation) do
      {:ok, set} ->
        new_set = Enum.reduce(tuples, set, &MapSet.put(&2, &1))
        %{state | relations: Map.put(rels, relation, new_set)}

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc """
  Checks whether a tuple exists in a relation.

  Returns `true` if `tuple` is a member of the `relation`'s MapSet,
  `false` otherwise. Returns `false` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec member?(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.tuple_values()) ::
          boolean()
  def member?(%__MODULE__{relations: rels}, relation, tuple) do
    case Map.fetch(rels, relation) do
      {:ok, set} -> MapSet.member?(set, tuple)
      :error -> false
    end
  end

  @doc """
  Returns the number of tuples stored in a relation.

  Returns `0` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec size(t(), ExDatalog.Storage.relation_name()) :: non_neg_integer()
  def size(%__MODULE__{relations: rels}, relation) do
    case Map.fetch(rels, relation) do
      {:ok, set} -> MapSet.size(set)
      :error -> 0
    end
  end

  @doc """
  Returns all tuples in a relation as a list.

  Used by the engine to iterate over a relation's facts during join
  evaluation. Returns `[]` if `relation` is unknown.
  """
  @impl ExDatalog.Storage
  @spec stream(t(), ExDatalog.Storage.relation_name()) :: Enumerable.t()
  def stream(%__MODULE__{relations: rels}, relation) do
    case Map.fetch(rels, relation) do
      {:ok, set} -> MapSet.to_list(set)
      :error -> []
    end
  end

  @doc false
  @impl ExDatalog.Storage
  @spec get_indexed(
          t(),
          ExDatalog.Storage.relation_name(),
          ExDatalog.Storage.index_key(),
          ExDatalog.Storage.key_values()
        ) ::
          Enumerable.t()
  def get_indexed(%__MODULE__{indexes: indexes}, relation, columns, key) do
    case Map.fetch(indexes, {relation, columns}) do
      {:ok, index} ->
        case Map.fetch(index, key) do
          {:ok, set} -> MapSet.to_list(set)
          :error -> []
        end

      :error ->
        []
    end
  end

  @doc false
  @impl ExDatalog.Storage
  @spec build_index(t(), ExDatalog.Storage.relation_name(), ExDatalog.Storage.index_key()) :: t()
  def build_index(%__MODULE__{relations: rels, indexes: indexes} = state, relation, columns) do
    case Map.fetch(rels, relation) do
      {:ok, set} ->
        index = build_index_from_set(set, columns)
        %{state | indexes: Map.put(indexes, {relation, columns}, index)}

      :error ->
        raise ArgumentError, "unknown relation #{inspect(relation)}"
    end
  end

  @doc false
  @impl ExDatalog.Storage
  @spec update_index(
          t(),
          ExDatalog.Storage.relation_name(),
          ExDatalog.Storage.index_key(),
          Enumerable.t()
        ) :: t()
  def update_index(
        %__MODULE__{indexes: indexes, relations: rels} = state,
        relation,
        columns,
        delta
      ) do
    key = {relation, columns}

    base_index =
      case Map.fetch(indexes, key) do
        {:ok, idx} ->
          idx

        :error ->
          case Map.fetch(rels, relation) do
            {:ok, set} -> build_index_from_set(set, columns)
            :error -> %{}
          end
      end

    updated_index =
      Enum.reduce(delta, base_index, fn tuple, idx ->
        k = project_tuple(tuple, columns)
        Map.update(idx, k, MapSet.new([tuple]), &MapSet.put(&1, tuple))
      end)

    %{state | indexes: Map.put(indexes, key, updated_index)}
  end

  @doc """
  Returns a sorted list of all relation names in the storage.

  Useful for debugging and introspection.
  """
  @impl ExDatalog.Storage
  @spec relations(t()) :: [ExDatalog.Storage.relation_name()]
  def relations(%__MODULE__{schemas: schemas}) do
    schemas |> Map.keys() |> Enum.sort()
  end

  # Builds a column-indexed lookup: %{composite_key => MapSet.t(tuple)}.
  # Used by build_index (full rebuild) and as the fallback in update_index
  # when no base index exists for the given key columns.
  defp build_index_from_set(set, columns) do
    Enum.reduce(set, %{}, fn tuple, idx ->
      k = project_tuple(tuple, columns)
      Map.update(idx, k, MapSet.new([tuple]), &MapSet.put(&1, tuple))
    end)
  end

  defp project_tuple(tuple, columns) do
    columns
    |> Enum.map(&elem(tuple, &1))
    |> List.to_tuple()
  end
end
