defmodule ExDatalog.Storage.ETSConformanceTest do
  @moduledoc """
  Conformance tests for the ETS storage backend.

  Uses the shared BackendConformance macro to verify that
  ExDatalog.Storage.ETS satisfies the Storage behaviour contract.
  """
  use ExUnit.Case, async: true

  import ExDatalog.Storage.BackendConformance

  backend_conformance_tests(ExDatalog.Storage.ETS)
end
