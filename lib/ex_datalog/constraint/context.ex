defmodule ExDatalog.Constraint.Context do
  @moduledoc """
  Evaluation context passed to constraint implementations.

  The context carries metadata about the current evaluation environment,
  including backend capabilities and provenance tracking settings. Constraint
  implementations can inspect the context to make decisions about evaluation
  (e.g., a future Z3 constraint might check `external_execution` capability).

  For v0.2.0, the context is informational — no constraint implementation
  branches on it. It is reserved for future use.
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
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Creates a new context with the given capabilities.
  """
  @spec new(Capabilities.t()) :: t()
  def new(%Capabilities{} = capabilities), do: %__MODULE__{capabilities: capabilities}

  @doc """
  Creates a new context with the given capabilities and provenance flag.
  """
  @spec new(Capabilities.t(), boolean()) :: t()
  def new(%Capabilities{} = capabilities, provenance) when is_boolean(provenance) do
    %__MODULE__{capabilities: capabilities, provenance: provenance}
  end
end
