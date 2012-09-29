\set ECHO 0
\i sql/index_analyzer.sql
\set ECHO all

-- can't be executed in a trasaction because we need stats to be updated

-- create table with an indexes, fill it with enough data
CREATE TABLE main_table(col_a INT PRIMARY KEY);
CREATE TABLE child_table(col_a INT, col_b INT REFERENCES main_table(col_a));

-- run basic test on the main table - nothing should be reported
SELECT * FROM analyze_fks('main_table'::regclass);

-- run basic test on the child table - a missing index should be reported
SELECT * FROM analyze_fks('child_table'::regclass);

-- create index on the child table, rerun the check
CREATE INDEX child_idx ON child_table(col_b);

-- run basic test on the child table - nothing should be reported
SELECT * FROM analyze_fks('child_table'::regclass);

-- perform CLEANUP
DROP TABLE child_table;
DROP TABLE main_table;

