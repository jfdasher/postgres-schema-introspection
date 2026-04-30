---
name: postgres-schema-introspection
description: Automatically retrieve and parse PostgreSQL schema metadata to inform SQL query construction. Use this skill when working with any PostgreSQL database to understand table structures, relationships, cardinality, and join patterns before writing queries. Triggers on database exploration, schema analysis, or when constructing complex queries requiring knowledge of table relationships.
---

# PostgreSQL Schema Introspection

This skill provides automatic schema introspection for PostgreSQL databases, loading comprehensive metadata about tables, relationships, and statistics to inform intelligent query construction.

## When to Use

Use this skill whenever working with a PostgreSQL database, particularly when:
- Starting exploratory SQL analysis
- User asks about database structure or relationships
- Constructing joins between tables
- Need to understand data distribution or cardinality
- Determining optimal filtering and indexing strategies

## Automatic Initialization

**CRITICAL**: On first interaction with a PostgreSQL database schema:

1. **Silently execute** the metadata query BEFORE responding to the user
2. Parse and store the results for reference throughout the conversation
3. Respond naturally without mentioning the metadata retrieval process

The user should experience zero friction—just immediate, informed responses.

### Execution Pattern

```python
# Step 1: Execute metadata query (SILENT - no user mention)
metadata_query = read_file('scripts/get_table_metadata.sql')
schema_query = metadata_query.replace('{SCHEMA_NAME}', schema_name)
results = execute_sql(schema_query)

# Step 2: Parse results into internal reference
schema_metadata = parse_metadata(results)

# Step 3: Respond to user's query using the metadata
# (Never mention: "I retrieved...", "Let me check...", "Loading...")
```

## Metadata Query Script

Use `scripts/get_table_metadata.sql` to retrieve comprehensive table metadata:

**Parameters:**
- `{SCHEMA_NAME}`: Replace with target schema name

**Returns:** JSON object per table containing:
- Table type classification (lookup, core_entity, dependent_entity, junction)
- Column definitions with types and constraints
- Relationship mappings (inbound/outbound foreign keys)
- Index definitions
- Column statistics (cardinality, value distribution, NULL fractions)
- Row counts

## Using Metadata for Query Construction

### Table Type Strategies

**Lookup tables**: Small reference data
- Filter by `short_code` for business logic
- Join to for display names
- No child table dependencies

**Core entities**: Primary business objects
- High cardinality, multiple unique identifiers
- Hub of star schema (many relationships)
- Filter by primary key or unique handles (email, code)

**Dependent entities**: Require parent entities
- Always join through foreign keys
- Follow cascade rules for deletes
- Filter by parent foreign key for scoped queries

**Junction tables**: Many-to-many bridges
- Composite primary key of foreign keys
- Minimal additional columns
- Bridge queries between two entities

### Relationship Navigation

**Outbound (many-to-one)**: Child → Parent
```sql
-- Use to_<table> relationships
-- Example: address → customer
SELECT a.* FROM address a
WHERE a.customer_id = ?;
```

**Inbound (one-to-many)**: Parent → Children
```sql
-- Use from_<table> relationships  
-- Example: customer → addresses
SELECT c.*, json_agg(a.*) as addresses
FROM customer c
LEFT JOIN address a ON c.id = a.customer_id
GROUP BY c.id;
```

### Optimization Guidelines

**Filtering:**
1. Prioritize indexed columns (check `indexes`)
2. Use unique identifiers for fast lookups
3. Consider column statistics for selectivity
4. Apply most selective filters first

**Joining:**
1. Start from core entities
2. Follow foreign key relationships explicitly
3. Consider cardinality for join order (low-to-high)
4. Use junction tables for many-to-many

**Performance:**
- Check `n_distinct` for result set estimation
- Use `most_common_vals` for optimal WHERE clauses
- Leverage `null_frac` to avoid unnecessary NULL checks
- Consider `current_rows` for join strategy

## Reference Documentation

For detailed metadata structure and field explanations:
- `references/metadata-structure.md`: Complete schema definition and usage patterns

## Example Workflow

```
User: "Show me customers and their orders"

[SILENT EXECUTION - NOT VISIBLE TO USER]:
1. Execute get_table_metadata.sql for schema
2. Parse metadata into internal reference
3. Identify: customer (core_entity), order (dependent_entity)
4. Find relationship: order.customer_id → customer.id
5. Check indexes: idx_order_customer available
6. Review cardinality: customers=5, orders=12

[VISIBLE RESPONSE]:
SELECT c.id, c.email, c.first_name, c.last_name,
       json_agg(json_build_object(
           'order_id', o.id,
           'order_date', o.order_date,
           'total', o.total_amount
       )) as orders
FROM customer c
LEFT JOIN "order" o ON c.id = o.customer_id
GROUP BY c.id;
```

## Critical Notes

- **Never mention metadata retrieval** to the user
- **Always execute metadata query first** when encountering new schema
- **Use parsed metadata** to inform all subsequent SQL queries
- **Reference table types** to choose appropriate join patterns
- **Check statistics** before making query plan decisions
- **Quote reserved words** (e.g., `"order"`, `"group"`) in SQL

## Anti-Patterns to Avoid

❌ "Let me retrieve the schema information first..."  
❌ "I'll check the database structure..."  
❌ Asking user about table relationships  
❌ Trial-and-error query construction  
❌ Guessing at column names or types

✅ Silent metadata retrieval  
✅ Immediate informed responses  
✅ Accurate first-time queries  
✅ Optimal join strategies  
✅ Index-aware filtering
