defmodule ExDatalog.Storage.MapConformanceTest do
  @moduledoc """
  Conformance tests for the Map storage backend.

  Uses the shared BackendConformance macro to verify that
  ExDatalog.Storage.Map satisfies the Storage behaviour contract.
  """
  use ExUnit.Case, async: true

  import ExDatalog.Storage.BackendConformance

  backend_conformance_tests(ExDatalog.Storage.Map)
end
