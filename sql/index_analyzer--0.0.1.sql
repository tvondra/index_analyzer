/*
 * Author: Tomas Vondra <tv@fuzzy.cz>
 * Created at: Fri Sep 28 05:06:28 +0200 2012
 *
 */ 

-- FIXME handle partial indexes properly (use index.reltuples instead of table.reltuples)
-- FIXME write a function to analyze possible indexes on specified columns (even partial, using MCV stats)

CREATE OR REPLACE FUNCTION analyze_tables(p_schema TEXT, p_min_selectivity FLOAT)
    RETURNS TABLE(relname TEXT, idxname TEXT, reason TEXT, selectivity FLOAT, ndistinct INT, nrows FLOAT, npages INT) AS $$
DECLARE
    r record;
    s record;
BEGIN

    FOR r IN (SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON (c.relnamespace = n.oid) WHERE nspname = p_schema AND relkind = 'r') LOOP
        FOR s IN (SELECT * FROM analyze_table(r.oid, p_min_selectivity)) LOOP

            relname := s.relname;
            idxname := s.idxname;
            selectivity := s.selectivity;
            ndistinct := s.ndistinct;
            nrows := s.nrows;
            npages := s.npages;
            reason := s.reason;
            RETURN NEXT;

        END LOOP;
    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;

-- analyzes all indexes on the table, identified by an OID
CREATE OR REPLACE FUNCTION analyze_table(p_table_oid OID, p_min_selectivity FLOAT)
    RETURNS TABLE(relname TEXT, idxname TEXT, reason TEXT, selectivity FLOAT, ndistinct INT, nrows FLOAT, npages INT) AS $$
DECLARE
    r record;
    s record;
BEGIN

    FOR r IN (SELECT indexrelid FROM pg_index WHERE indrelid = p_table_oid) LOOP

        -- basic stats
        FOR s IN (SELECT * FROM analyze_index(r.indexrelid, p_min_selectivity)) LOOP
            relname := s.relname;
            idxname := s.idxname;
            selectivity := s.selectivity;
            ndistinct := s.ndistinct;
            nrows := s.nrows;
            npages := s.npages;
            reason := s.reason;
            RETURN NEXT;
        END LOOP;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;

-- analyzes a single indexe, identified by an OID
CREATE OR REPLACE FUNCTION analyze_index(p_index_oid OID, p_min_selectivity FLOAT)
    RETURNS TABLE(relname TEXT, idxname TEXT, reason TEXT, selectivity FLOAT, ndistinct INT, nrows FLOAT, npages INT) AS $$
DECLARE
    s record;
BEGIN

    -- basic stats
    FOR s IN (SELECT * FROM analyze_index_selectivity(p_index_oid, p_min_selectivity)) LOOP
        relname := s.relname;
        idxname := s.idxname;
        selectivity := s.selectivity;
        ndistinct := s.ndistinct;
        nrows := s.nrows;
        npages := s.npages;
        reason := s.reason;
        RETURN NEXT;
    END LOOP;

        -- usage
    FOR s IN (SELECT * FROM analyze_index_usage(p_index_oid)) LOOP
        relname := s.relname;
        idxname := s.idxname;
        selectivity := s.selectivity;
        ndistinct := s.ndistinct;
        nrows := s.nrows;
        npages := s.npages;
        reason := s.reason;
        RETURN NEXT;
    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;



-- analyzes one index, identified by an OID - uses only info from the system catalogs
CREATE OR REPLACE FUNCTION analyze_index_selectivity(p_index_oid OID, p_min_selectivity FLOAT)
    RETURNS TABLE(relname TEXT, idxname TEXT, reason TEXT, selectivity FLOAT, ndistinct INT, nrows FLOAT, npages INT) AS $$
DECLARE
    r RECORD;
    no_data BOOLEAN := true;
BEGIN

    ndistinct := 1;

    FOR r IN (SELECT
                    indrelid, c.relname, i.relname as idxname, col, a.attname,
                    (CASE WHEN n_distinct > 0 THEN n_distinct ELSE -n_distinct*c.reltuples END) AS n_distinct,
                    null_frac, c.reltuples, i.relpages, correlation
                FROM (SELECT indrelid, indexrelid, unnest(indkey::int[]) AS col FROM pg_index WHERE indexrelid = p_index_oid) foo
                JOIN pg_attribute a ON (foo.indrelid = a.attrelid AND col = a.attnum)
                JOIN pg_class c ON (indrelid = c.oid)
                JOIN pg_class i ON (foo.indexrelid = i.oid)
                JOIN pg_stats s ON (c.relname = s.tablename and a.attname = s.attname)) LOOP
        
        no_data := false;
        ndistinct := ndistinct * r.n_distinct;
        nrows := r.reltuples;
        relname := r.relname;
        idxname := r.idxname;
        npages := r.relpages;

    END LOOP;

    -- no stats found
    IF no_data THEN
        RETURN;
    END IF;

    selectivity := round(100 / ndistinct::float);

    IF (selectivity > p_min_selectivity) THEN
        reason := 'low selectivity';
        RETURN NEXT;
    ELSIF (npages < 100) THEN
        reason := 'small table';
        RETURN NEXT;
    END IF;

    RETURN;

END;
$$ LANGUAGE plpgsql;

-- analyzes one index, identified by an OID - uses only info from the system catalogs
CREATE OR REPLACE FUNCTION analyze_index_usage(p_index_oid OID)
    RETURNS TABLE(relname TEXT, idxname TEXT, reason TEXT, selectivity FLOAT, ndistinct INT, nrows FLOAT, npages INT) AS $$
DECLARE
    index_info  RECORD; -- index info
    index_stats RECORD; -- index stats
    table_stats RECORD; -- table stats
BEGIN

    ndistinct := 1;

    -- get info about the index
    SELECT pg_index.*, i.relname AS idxname, r.relname, r.reltuples, i.relpages INTO index_info
      FROM pg_index JOIN pg_class r ON (indrelid = r.oid)
                    JOIN pg_class i ON (indexrelid = i.oid)
     WHERE indexrelid = p_index_oid;

    -- get index stats (basic + I/O)
    SELECT * INTO index_stats
      FROM pg_stat_all_indexes s JOIN pg_statio_all_indexes i ON (s.relid = i.relid AND s.indexrelid = i.indexrelid)
     WHERE s.indexrelid = index_info.indexrelid;

    -- get table stats (basic + I/O)
    SELECT * INTO table_stats
      FROM pg_stat_all_tables s JOIN pg_statio_all_tables i ON (s.relid = i.relid)
     WHERE s.relid = index_info.indrelid;

    IF index_info.indisunique THEN
        -- don't check unique indexes - they are used in the background
        RETURN;
    ELSIF index_stats.idx_scan = 0 THEN
        -- not used at all
        ndistinct := NULL;
        nrows := index_info.reltuples;
        relname := index_info.relname;
        idxname := index_info.idxname;
        npages := index_info.relpages;
        reason := 'not used by queries';
        RETURN NEXT;
    ELSIF index_stats.idx_scan < table_stats.seq_scan/10 THEN
        ndistinct := NULL;
        nrows := index_info.reltuples;
        relname := index_info.relname;
        idxname := index_info.idxname;
        npages := index_info.relpages;
        reason := 'only rarely used by queries';
        RETURN NEXT;
    END IF;

    RETURN;

END;
$$ LANGUAGE plpgsql;

-- count distinct combinations of values in the index
-- FIXME this should sample the table randomly instead of reading all of it
-- FIXME this doesn't work too well with expression indexes (so it's disabled not to give bad results)
CREATE OR REPLACE FUNCTION analyze_index_count_distinct(p_index_oid OID)
    RETURNS int AS $$
DECLARE
    r           RECORD;
    sql         TEXT;
    relname     TEXT;
    ndistinct   INT;
    first_col   BOOLEAN := true;
BEGIN

    sql := 'SELECT COUNT(DISTINCT (';

    FOR r IN (SELECT col, i.relname AS idxname, c.relname, a.attname
                FROM (SELECT indrelid, indexrelid, unnest(indkey::int[]) AS col FROM pg_index WHERE indexrelid = p_index_oid) foo
                     JOIN pg_class i ON (indexrelid = i.oid)
                LEFT JOIN pg_attribute a ON (foo.indrelid = a.attrelid AND col = a.attnum)
                LEFT JOIN pg_class c ON (indrelid = c.oid)) LOOP

        relname := r.relname;

        -- FIXME can't estimate expression indexes right now
        IF r.col = 0 THEN
            -- FIXME actually we might compute it using actual columns and if the selectivity is
            -- good enough, then we're safe because adding another column may not make it worse
            RAISE NOTICE 'index ''%s'' is an expression index - not possible to count distinct vals',r.idxname;
            RETURN NULL;
        END IF;

        IF first_col THEN
            sql := sql || quote_ident(r.attname);
            first_col := false;
        ELSE
            sql := sql || ', ' || quote_ident(r.attname);
        END IF;
        
    END LOOP;

    sql := sql || ')) AS cnt FROM ' || quote_ident(relname);

    EXECUTE sql INTO ndistinct;

    RETURN ndistinct;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION analyze_fks(p_schema TEXT)
    RETURNS TABLE(relname TEXT, refrelname TEXT, fkname TEXT, result TEXT) AS $$
DECLARE
    r   RECORD;
    s   RECORD;
BEGIN

    FOR r IN (SELECT c.oid, c.relname FROM pg_class c JOIN pg_namespace n ON (c.relnamespace = n.oid) WHERE nspname = p_schema AND relkind = 'r') LOOP
        FOR s IN (SELECT * FROM analyze_fks(r.oid)) LOOP

            relname := s.relname;
            refrelname := s.refrelname;
            fkname := s.fkname;
            result := s.result;
            RETURN NEXT;

        END LOOP;
    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION analyze_fks(p_table_oid OID)
    RETURNS TABLE(relname TEXT, refrelname TEXT, fkname TEXT, result TEXT) AS $$
DECLARE
    r   RECORD;
BEGIN

    FOR r IN (SELECT c.oid, a.relname, b.relname AS refrelname, c.conname AS fkname
                FROM pg_constraint c JOIN pg_class a ON (c.conrelid = a.oid)
                                     JOIN pg_class b ON (c.confrelid = b.oid)
                WHERE conrelid = p_table_oid) LOOP

        IF NOT analyze_fk(r.oid) THEN

            relname := r.relname;
            refrelname := r.refrelname;
            fkname := r.fkname;
            result := 'no index on the FK columns';
            RETURN NEXT;

        END IF;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;

-- check that there are indexes on the child table (unless very small or low cardinality)
-- FIXME consider cardinality of the columns too (not to suggest indexes on FKs with low cardinality)
CREATE OR REPLACE FUNCTION analyze_fk(p_fk_oid OID)
    RETURNS boolean AS $$
DECLARE
    v_found BOOLEAN := false;
BEGIN

    -- exact index match
    SELECT true INTO v_found FROM pg_constraint JOIN pg_index ON ((conrelid = indrelid) AND
                                                                  (conkey::int[] @> indkey::int[]) AND
                                                                  (conkey::int[] <@ indkey::int[]))
                            WHERE pg_constraint.oid = p_fk_oid;

    IF v_found THEN
        -- there''s an index for the FK
        RETURN true;
    END IF;

    -- superindex (index with all the FK colums and some additional)
    SELECT true INTO v_found FROM pg_constraint JOIN pg_index ON ((conrelid = indrelid) AND
                                                                  (conkey::int[] <@ indkey::int[]))
                            WHERE pg_constraint.oid = p_fk_oid;

    IF v_found THEN
        -- there''s a super-index for the FK (more columns than in the FK)
        RETURN true;
    END IF;

    -- sub-index (index with some of the FK columns)
    SELECT true INTO v_found FROM pg_constraint JOIN pg_index ON ((conrelid = indrelid) AND
                                                                  (conkey::int[] <@ indkey::int[]))
                            WHERE pg_constraint.oid = p_fk_oid;

    IF v_found THEN
        -- there''s a sub-index for the FK (less columns than in the FK
        RETURN true;
    END IF;

    RETURN false;

END;
$$ LANGUAGE plpgsql;

-- check one foreign key by name
CREATE OR REPLACE FUNCTION analyze_fk(p_fk_name TEXT)
    RETURNS TABLE(relname TEXT, refrelname TEXT, fkname TEXT, result TEXT) AS $$
DECLARE
    r   RECORD;
BEGIN

    FOR r IN (SELECT c.oid, a.relname, b.relname AS refrelname, c.conname AS fkname
                FROM pg_constraint c JOIN pg_class a ON (c.conrelid = a.oid)
                                     JOIN pg_class b ON (c.confrelid = b.oid)
                WHERE conname = p_fk_name) LOOP

        IF NOT analyze_fk(r.oid) THEN

            relname := r.relname;
            refrelname := r.refrelname;
            fkname := r.fkname;
            result := 'no index on the FK columns';
            RETURN NEXT;

        END IF;

    END LOOP;

    RETURN;

END;
$$ LANGUAGE plpgsql;
