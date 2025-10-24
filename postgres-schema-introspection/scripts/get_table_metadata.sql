-- COMPREHENSIVE TABLE METADATA QUERY
-- Returns semantic information about tables including relationships, 
-- cardinality, identifiers, indexes, constraints, and column statistics
-- 
-- CONFIGURATION: Change the target_schema value in the schema_config CTE below
-- USAGE: Remove WHERE clause and LIMIT to get all tables

WITH 
-- ═══════════════════════════════════════════════════════════════
-- CONFIGURATION: Set target schema here (ONLY PLACE TO CHANGE)
-- ═══════════════════════════════════════════════════════════════
schema_config AS (
  SELECT '{SCHEMA_NAME}'::text AS target_schema
),

-- Table classification heuristic
table_types AS (
  SELECT t.table_schema, t.table_name,
    CASE
      WHEN (SELECT COUNT(*) FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
            WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
            AND tc.constraint_type = 'PRIMARY KEY') >= 2
           AND (SELECT COUNT(*) FROM information_schema.key_column_usage kcu_pk
                WHERE kcu_pk.table_schema = t.table_schema AND kcu_pk.table_name = t.table_name
                AND kcu_pk.constraint_name IN (SELECT constraint_name FROM information_schema.table_constraints
                                               WHERE table_schema = t.table_schema AND table_name = t.table_name
                                               AND constraint_type = 'PRIMARY KEY')
                AND kcu_pk.column_name IN (SELECT column_name FROM information_schema.key_column_usage kcu_fk
                                          WHERE kcu_fk.table_schema = t.table_schema AND kcu_fk.table_name = t.table_name
                                          AND kcu_fk.constraint_name IN (SELECT constraint_name FROM information_schema.table_constraints
                                                                        WHERE table_schema = t.table_schema AND table_name = t.table_name
                                                                        AND constraint_type = 'FOREIGN KEY'))) =
               (SELECT COUNT(*) FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
                AND tc.constraint_type = 'PRIMARY KEY')
           AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = t.table_schema AND table_name = t.table_name) <= 
               (SELECT COUNT(*) FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
                AND tc.constraint_type = 'PRIMARY KEY') + 2
      THEN 'junction_table'
      WHEN EXISTS(SELECT 1 FROM information_schema.columns c1
                  JOIN information_schema.columns c2 ON c1.table_schema = c2.table_schema AND c1.table_name = c2.table_name
                  WHERE c1.table_schema = t.table_schema AND c1.table_name = t.table_name
                  AND c1.column_name = 'short_code' AND c2.column_name = 'display_name')
           AND (SELECT COUNT(DISTINCT kcu.column_name) FROM information_schema.table_constraints tc
                JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
                WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
                AND tc.constraint_type = 'FOREIGN KEY') = 0
           AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = t.table_schema AND table_name = t.table_name) <= 4
      THEN 'lookup_table'
      WHEN (SELECT COUNT(DISTINCT tc.table_name) FROM information_schema.table_constraints tc
            JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
            WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_schema = t.table_schema AND ccu.table_name = t.table_name) >= 2
           OR (EXISTS(SELECT 1 FROM information_schema.columns c1
                     JOIN information_schema.columns c2 ON c1.table_schema = c2.table_schema AND c1.table_name = c2.table_name
                     WHERE c1.table_schema = t.table_schema AND c1.table_name = t.table_name
                     AND c1.column_name = 'short_code' AND c2.column_name = 'display_name')
               AND (SELECT COUNT(*) FROM information_schema.columns WHERE table_schema = t.table_schema AND table_name = t.table_name) > 4)
      THEN 'core_entity'
      WHEN (SELECT COUNT(DISTINCT kcu.column_name) FROM information_schema.table_constraints tc
            JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
            WHERE tc.table_schema = t.table_schema AND tc.table_name = t.table_name
            AND tc.constraint_type = 'FOREIGN KEY') >= 1
      THEN 'dependent_entity'
      ELSE 'core_entity'
    END AS table_type
  FROM information_schema.tables t
  CROSS JOIN schema_config sc
  WHERE t.table_schema = sc.target_schema AND t.table_type = 'BASE TABLE'
),
column_info AS (
  SELECT c.table_schema, c.table_name,
    jsonb_agg(jsonb_build_object('column_name', c.column_name, 'data_type', c.data_type, 
                                 'is_nullable', c.is_nullable, 'column_default', c.column_default,
                                 'ordinal_position', c.ordinal_position) ORDER BY c.ordinal_position) AS columns
  FROM information_schema.columns c
  CROSS JOIN schema_config sc
  WHERE c.table_schema = sc.target_schema
  GROUP BY c.table_schema, c.table_name
),
outbound_fks AS (
  SELECT tc.table_schema, tc.table_name,
    jsonb_object_agg('to_' || ccu.table_name,
      jsonb_build_object('type', 'many_to_one', 'foreign_table', ccu.table_name,
                        'local_column', kcu.column_name, 'foreign_column', ccu.column_name,
                        'join_condition', tc.table_name || '.' || kcu.column_name || ' = ' || ccu.table_name || '.' || ccu.column_name,
                        'on_delete', rc.delete_rule, 'on_update', rc.update_rule)) AS outbound_relationships
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
  JOIN information_schema.referential_constraints rc ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
  CROSS JOIN schema_config sc
  WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = sc.target_schema
  GROUP BY tc.table_schema, tc.table_name
),
inbound_fks AS (
  SELECT ccu.table_schema, ccu.table_name,
    jsonb_object_agg('from_' || tc.table_name,
      jsonb_build_object('type', 'one_to_many', 'referencing_table', tc.table_name,
                        'foreign_column', kcu.column_name, 'local_column', ccu.column_name,
                        'join_condition', ccu.table_name || '.' || ccu.column_name || ' = ' || tc.table_name || '.' || kcu.column_name,
                        'on_delete', rc.delete_rule, 'on_update', rc.update_rule)) AS inbound_relationships
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name AND tc.table_schema = ccu.table_schema
  JOIN information_schema.referential_constraints rc ON tc.constraint_name = rc.constraint_name AND tc.table_schema = rc.constraint_schema
  CROSS JOIN schema_config sc
  WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = sc.target_schema
  GROUP BY ccu.table_schema, ccu.table_name
),
unique_identifiers AS (
  SELECT tc.table_schema, tc.table_name,
    jsonb_agg(jsonb_build_object('column_name', kcu.column_name, 'data_type', c.data_type,
      'identifier_type', CASE WHEN c.column_name ILIKE '%code%' THEN 'business_code'
                              WHEN c.column_name ILIKE '%email%' THEN 'unique_handle'
                              WHEN c.data_type IN ('integer', 'bigint') AND c.column_default LIKE 'nextval%' THEN 'surrogate_key'
                              WHEN c.data_type IN ('character varying', 'character', 'text') THEN 'natural_key'
                              ELSE 'unique_identifier' END,
      'is_nullable', c.is_nullable)) AS unique_identifiers
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
  JOIN information_schema.columns c ON kcu.table_schema = c.table_schema AND kcu.table_name = c.table_name AND kcu.column_name = c.column_name
  CROSS JOIN schema_config sc
  WHERE tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY') AND tc.table_schema = sc.target_schema AND c.is_nullable = 'NO'
  GROUP BY tc.table_schema, tc.table_name
),
table_indexes AS (
  SELECT schemaname AS table_schema, tablename AS table_name,
    jsonb_agg(jsonb_build_object('index_name', indexname, 'index_definition', indexdef)) AS indexes
  FROM pg_indexes
  CROSS JOIN schema_config sc
  WHERE schemaname = sc.target_schema
  GROUP BY schemaname, tablename
),
check_constraints AS (
  SELECT tc.table_schema, tc.table_name,
    jsonb_agg(jsonb_build_object('constraint_name', tc.constraint_name, 'check_clause', cc.check_clause)) AS check_constraints
  FROM information_schema.table_constraints tc
  JOIN information_schema.check_constraints cc ON tc.constraint_name = cc.constraint_name AND tc.constraint_schema = cc.constraint_schema
  CROSS JOIN schema_config sc
  WHERE tc.constraint_type = 'CHECK' AND tc.table_schema = sc.target_schema
  GROUP BY tc.table_schema, tc.table_name
),
column_stats AS (
  SELECT schemaname AS table_schema, tablename AS table_name,
    jsonb_object_agg(attname, jsonb_build_object('n_distinct', n_distinct, 'most_common_vals', most_common_vals::text,
                                                 'most_common_freqs', most_common_freqs::text, 'null_frac', null_frac)) AS column_statistics
  FROM pg_stats
  CROSS JOIN schema_config sc
  WHERE schemaname = sc.target_schema AND (most_common_vals IS NOT NULL OR n_distinct IS NOT NULL)
  GROUP BY schemaname, tablename
),
row_counts AS (
  SELECT schemaname AS table_schema, relname AS table_name, n_live_tup AS current_rows
  FROM pg_stat_user_tables
  CROSS JOIN schema_config sc
  WHERE schemaname = sc.target_schema
)

SELECT tt.table_name,
  jsonb_build_object(
    'table_name', tt.table_name, 'schema', tt.table_schema, 'type', tt.table_type,
    'cardinality', jsonb_build_object('current_rows', COALESCE(rc.current_rows, 0)),
    'columns', COALESCE(ci.columns, '[]'::jsonb),
    'relationships', COALESCE(COALESCE(ob.outbound_relationships, '{}'::jsonb) || COALESCE(ib.inbound_relationships, '{}'::jsonb), '{}'::jsonb),
    'unique_identifiers', COALESCE(ui.unique_identifiers, '[]'::jsonb),
    'indexes', COALESCE(ti.indexes, '[]'::jsonb),
    'check_constraints', COALESCE(chk.check_constraints, '[]'::jsonb),
    'column_statistics', COALESCE(cs.column_statistics, '{}'::jsonb)
  ) AS metadata
FROM table_types tt
LEFT JOIN column_info ci USING (table_schema, table_name)
LEFT JOIN outbound_fks ob USING (table_schema, table_name)
LEFT JOIN inbound_fks ib USING (table_schema, table_name)
LEFT JOIN unique_identifiers ui USING (table_schema, table_name)
LEFT JOIN table_indexes ti USING (table_schema, table_name)
LEFT JOIN check_constraints chk USING (table_schema, table_name)
LEFT JOIN column_stats cs USING (table_schema, table_name)
LEFT JOIN row_counts rc USING (table_schema, table_name)
ORDER BY tt.table_name;
