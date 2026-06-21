defmodule ExDatalog.DSL.CompileError do
  @moduledoc """
  Raised when a DSL macro cannot be compiled.

  Errors include clear descriptions of what went wrong and where.

  ## Examples

      iex> raise ExDatalog.DSL.CompileError, message: "relation :parent is not declared"
      ** (ExDatalog.DSL.CompileError) relation :parent is not declared

      iex> err = ExDatalog.DSL.CompileError.exception("unsafe variable z")
      iex> err.message
      "unsafe variable z"

      iex> ExDatalog.DSL.CompileError.exception(message: "bad rule")
      %ExDatalog.DSL.CompileError{message: "bad rule"}
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}

  @impl true
  def exception(opts) when is_list(opts) do
    message = Keyword.get(opts, :message, "DSL compilation error")
    %__MODULE__{message: message}
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message}
  end
end
