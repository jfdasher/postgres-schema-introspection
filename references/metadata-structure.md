# Schema Metadata Structure Reference

This document explains the structure of the metadata returned by `get_table_metadata.sql`.

## Metadata Schema

Each table returns a JSON object with the following structure:

```json
{
  "table_name": "string",
  "schema": "string",
  "type": "lookup_table|core_entity|dependent_entity|junction_table",
  "cardinality": {
    "current_rows": number
  },
  "columns": [
    {
      "column_name": "string",
      "data_type": "string",
      "is_nullable": "YES|NO",
      "column_default": "string|null",
      "ordinal_position": number
    }
  ],
  "relationships": {
    "to_<table>": {
      "type": "many_to_one",
      "foreign_table": "string",
      "local_column": "string",
      "foreign_column": "string",
      "join_condition": "string",
      "on_delete": "CASCADE|RESTRICT|NO ACTION|SET NULL",
      "on_update": "CASCADE|RESTRICT|NO ACTION|SET NULL"
    },
    "from_<table>": {
      "type": "one_to_many",
      "referencing_table": "string",
      "foreign_column": "string",
      "local_column": "string",
      "join_condition": "string",
      "on_delete": "CASCADE|RESTRICT|NO ACTION|SET NULL",
      "on_update": "CASCADE|RESTRICT|NO ACTION|SET NULL"
    }
  },
  "unique_identifiers": [
    {
      "column_name": "string",
      "data_type": "string",
      "identifier_type": "surrogate_key|business_code|unique_handle|natural_key|unique_identifier",
      "is_nullable": "NO"
    }
  ],
  "indexes": [
    {
      "index_name": "string",
      "index_definition": "string"
    }
  ],
  "check_constraints": [
    {
      "constraint_name": "string",
      "check_clause": "string"
    }
  ],
  "column_statistics": {
    "<column_name>": {
      "n_distinct": number,
      "most_common_vals": "string|null",
      "most_common_freqs": "string|null",
      "null_frac": number
    }
  }
}
```

## Table Types

### lookup_table
Reference tables with `short_code` + `display_name` pattern. Small, static datasets.
- **Characteristics**: No foreign keys, 2-4 columns
- **Join pattern**: Referenced by many tables
- **Filter by**: `short_code` for business logic

### core_entity
Primary business objects that stand alone.
- **Characteristics**: Multiple unique identifiers, high cardinality
- **Join pattern**: Hub of relationships (many inbound/outbound FKs)
- **Filter by**: Primary key, unique identifiers (email, code)

### dependent_entity
Tables that require a parent entity.
- **Characteristics**: Foreign keys to core entities, cascade deletes
- **Join pattern**: Follow FK relationships from parent
- **Filter by**: Parent foreign key

### junction_table
Many-to-many relationship bridges.
- **Characteristics**: Composite PK of 2+ FKs, minimal additional columns
- **Join pattern**: Bridge between two entities
- **Filter by**: Either FK to access related entities

## Relationship Directions

### Outbound (many_to_one)
Child table → Parent table. Key in `to_<table>` format.
```sql
-- Example: address → customer
SELECT a.* FROM address a
WHERE a.customer_id = 5;
```

### Inbound (one_to_many)
Parent table ← Child tables. Key in `from_<table>` format.
```sql
-- Example: customer → addresses
SELECT c.*, json_agg(a.*) as addresses
FROM customer c
LEFT JOIN address a ON c.id = a.customer_id
GROUP BY c.id;
```

## Column Statistics

### n_distinct
- Negative values: Fraction of total rows (e.g., -0.5 = 50% distinct)
- Positive values: Estimated number of distinct values

### most_common_vals/freqs
Arrays showing most frequent values and their frequencies. Useful for:
- Identifying dominant categories
- Optimizing WHERE clauses
- Understanding data distribution

### null_frac
Fraction of NULL values (0.0 = no NULLs, 1.0 = all NULLs)

## Identifier Types

- **surrogate_key**: Auto-incrementing integer (nextval)
- **business_code**: Natural business identifier (e.g., SKU, product code)
- **unique_handle**: User-facing unique identifier (e.g., email, username)
- **natural_key**: Natural unique identifier from domain
- **unique_identifier**: Generic unique constraint

## Using Metadata for Query Construction

### Filtering Strategy
1. Check `unique_identifiers` for fast lookups
2. Use `indexes` to identify indexed columns
3. Review `column_statistics` for data distribution
4. Consider `cardinality.current_rows` for join order

### Join Strategy
1. Start from `core_entity` tables
2. Follow `outbound_relationships` (many-to-one) for child → parent
3. Follow `inbound_relationships` (one-to-many) for parent → children
4. Use `junction_table` for many-to-many

### Performance Optimization
- Filter on indexed columns first
- Use `n_distinct` to estimate result set sizes
- Consider `on_delete`/`on_update` rules for data integrity
- Leverage `most_common_vals` for query planning
