# PostgreSQL Schema Introspection

An auto-skill for Claude Code that retrieves PostgreSQL schema metadata to inform SQL query construction. This is a humble attempt to naively interpolate entity semantics using `pg_stats` data alongside standard catalog queries—a pattern applicable to any RDBMS and coding agent.

## Overview

When working with an unfamiliar PostgreSQL schema, this skill automatically queries catalog tables and `pg_stats` to understand table structures, relationships, cardinality, and data distribution.

## Contents

- `SKILL.md` — Skill definition with table type heuristics and query patterns
- `scripts/get_table_metadata.sql` — Parameterized metadata query template
- `references/metadata-structure.md` — Complete output schema reference

## Requirements

- PostgreSQL with `pg_stats` access
- Catalog read permissions (`information_schema`, `pg_catalog`)

## Auto-Skill Behavior

The skill engages automatically when you mention a schema name and ask about its data. No explicit commands needed.

## Using the SQL Directly

Replace `{SCHEMA_NAME}` in `scripts/get_table_metadata.sql` with your target schema and execute. Returns JSON metadata per table suitable for programmatic consumption.
