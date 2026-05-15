defmodule ExDatalog.Constraint.Context do
  @moduledoc """
  Evaluation context passed to constraint implementations.

  The context carries metadata about the current evaluation environment,
  including backend capabilities and provenance tracking settings.

  ## v0.2.0 status

  For v0.2.0, the context is **informational only** — no constraint
  implementation reads from it. It is reserved for future constraint types
  that may need to inspect capabilities (e.g., a future Z3 backend checking
  `external_execution`) or provenance metadata.

  Do not remove this module: it is part of the public `Constraint.evaluate/3`
  signature and will be used in a future release.
  """

  alias ExDatalog.Capabilities

  @type t :: %__MODULE__{
          capabilities: Capabilities.t(),
          provenance: boolean()
        }

  defstruct capabilities: %Capabilities{},
            provenance: false

  @doc """
  Creates a new context with default capabilities.

  ## Examples

      iex> ctx = ExDatalog.Constraint.Context.new()
      iex> ctx.capabilities.storage_type
      :map
      iex> ctx.provenance
      false

  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new context with the given capabilities.

  ## Examples

      iex> caps = %ExDatalog.Capabilities{storage_type: :ets, indexed_lookup: true}
      iex> ctx = ExDatalog.Constraint.Context.new(caps)
      iex> ctx.capabilities.storage_type
      :ets
      iex> ctx.provenance
      false

  """
  @spec new(Capabilities.t()) :: t()
  def new(%Capabilities{} = capabilities), do: %__MODULE__{capabilities: capabilities}

  @doc """
  Creates a new context with the given capabilities and provenance flag.

  ## Examples

      iex> caps = %ExDatalog.Capabilities{storage_type: :ets}
      iex> ctx = ExDatalog.Constraint.Context.new(caps, true)
      iex> ctx.provenance
      true

  """
  @spec new(Capabilities.t(), boolean()) :: t()
  def new(%Capabilities{} = capabilities, provenance) when is_boolean(provenance) do
    %__MODULE__{capabilities: capabilities, provenance: provenance}
  end
end
