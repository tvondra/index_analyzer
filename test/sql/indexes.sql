\set ECHO 0
\i sql/index_analyzer.sql
\set ECHO all

-- can't be executed in a trasaction because we need stats to be updated

-- create table with an indexes, fill it with enough data
CREATE TABLE test_table (col_a INT, col_b INT, col_c INT);
INSERT INTO test_table SELECT i, mod(i,20), mod(i,5) FROM generate_series(1,50000) s(i);

CREATE INDEX test_index_1 ON test_table(col_a);
CREATE INDEX test_index_2 ON test_table(col_b);
CREATE INDEX test_index_3 ON test_table(col_c);

-- analyze to get good selectivity estimates
ANALYZE test_table;

-- run basic test on the schema - all three should be reported (not yet used)
SELECT * FROM analyze_table('test_table'::regclass, 10.0);

-- should be OK - basically a unique index
SELECT * FROM analyze_index('test_index_1'::regclass, 1.0);

-- should be OK - the selectivity is ~5% (but depends on estimate accuracy)
SELECT * FROM analyze_index('test_index_2'::regclass, 10.0);

-- should not be OK (selectivity ~5%)
SELECT * FROM analyze_index('test_index_2'::regclass, 1.0);

-- should not be OK (selectivity ~20%)
SELECT * FROM analyze_index('test_index_3'::regclass, 5.0);

-- use the indexes
SELECT 1 FROM test_table WHERE col_a = -1;
SELECT 1 FROM test_table WHERE col_b = -1;
SELECT 1 FROM test_table WHERE col_c = -1;

-- sleep for a while, to get the stats updated
SELECT pg_sleep(1);

-- repeat the tests - there should be no "not used by queries" messages

-- run basic test on the schema - all three should be reported (not yet used)
SELECT * FROM analyze_table('test_table'::regclass, 10.0);

-- should be OK - basically a unique index
SELECT * FROM analyze_index('test_index_1'::regclass, 1.0);

-- should be OK - the selectivity is ~5% (but depends on estimate accuracy)
SELECT * FROM analyze_index('test_index_2'::regclass, 10.0);

-- should not be OK (selectivity ~5%)
SELECT * FROM analyze_index('test_index_2'::regclass, 1.0);

-- should not be OK (selectivity ~20%)
SELECT * FROM analyze_index('test_index_3'::regclass, 5.0);