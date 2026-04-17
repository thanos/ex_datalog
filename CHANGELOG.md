# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - Unreleased

### Added

- Phase 0: Architecture and design blueprint (pure Elixir, semi-naive evaluation, storage behaviour, hash-join indexing)
- Phase 1: AST, DSL, and term model
  - `ExDatalog.Term` — `var/1`, `const/1`, `wildcard/0`, guards, and validation
  - `ExDatalog.Constraint` — comparison (`gt`, `lt`, `gte`, `lte`, `eq`, `neq`) and arithmetic (`add`, `sub`, `mul`, `div`) constructors
  - `ExDatalog.Atom` — relation references with terms
  - `ExDatalog.Rule` — `%Rule{head, body, constraints}` with polarity on body literals
  - `ExDatalog.Program` — builder pipeline (`new/0`, `add_relation/3`, `add_fact/2`, `add_rule/2`)
  - `ExDatalog.Validator` — Phase 1 structural validation (arity, relation existence, term validity)
  - `ExDatalog.Validator.Errors` — structured error types with kind, context, and message

[0.1.0]: https://github.com/anomalyco/ex_datalog/releases/tag/v0.1.0