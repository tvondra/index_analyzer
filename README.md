index_analyzer
==============

A package that might help you if you need to evaluate the existing
or considered indexes. So these functions may be useful for you if
you need to know which indexes are not used at all (thus slowing
down modifications and occupy space on the drive but not helping
the queries) or might be useful if created.

These answers are not definitive though, because indexes may be
used in many ways and and unused for many reasons - for example
the way the queries are written and so on.

The functions check only user tables, not system catalogs.


analysis of existing indexes
----------------------------

These functions are used to check existing indexes - estimate
selectivity, check how often the indexes are used etc.

 * **analyze\_tables**`(p_schema TEXT, p_min_selectivity FLOAT)`

    Analyzes existing indexes on all user tables in the given schema.

 * **analyze\_table**`(p_table_oid OID, p_min_selectivity FLOAT)`

    Analyzes existing indexes on the given table.

 * **analyze\_index**`(p_index_oid OID, p_min_selectivity FLOAT)`

    Analyzes a single index (call some of the following functions).

 * **analyze\_index\_selectivity**`(p_index_oid OID,
                                    p_min_selectivity FLOAT)`

    Analyzes index selectivity, by estimating the number of distinct
    combinations from the system catalogs by multiplying the values
    for each column. This may suffer by overestimation for correlated
    columns.

    The `p_min_selectivity` is used to specify what selectivity (i.e.
    percentage of rows matching a condition) threshold - for higher
    values the index is considered ineffective. A reasonable value
    is 5% or something like that.

 * **analyze\_index\_usage**`(p_index_oid OID)`

    Checks usage statistics as recorded in the pg_stat_* catalogs and
    compares them to sequential scans.

    Unique indexes (incl. primary keys) are skipped, because these
    indexes serve other purposes.

 * **analyze\_index\_count\_distinct**`(p_index_oid OID)`

    Performs distinct estimation by sampling the table. Does not work
    too well for expression indexes (with at least one expression).
    Be careful, as this may be very expensive operation.


analysis of foreign keys
------------------------

These function are used to check that all foreign keys have indexes on
the referencing table.

 * **analyze\_fks**`(p_schema TEXT)`

    Analyzes all foreign keys on tables in the given schema.

 * **analyze\_fks**`(p_table_oid OID)`

    Analyzes all foreign keys on the given table (referencing other
    tables).

 * **analyze\_fk**`(p_fk_name TEXT)`

    Analyzes one foreign key by constraint name.

 * **analyze\_fk**`(p_fk_oid OID)`

    Analyzes one foreign key by OID.


Installation
------------
Installing this extension is very simple - if you're using pgxn client
(and you should), just do this:

    $ pgxn install --testing index_analyzer
    $ pgxn load --testing -d mydb index_analyzer

You can also install manually, just it like any other extension, i.e.

    $ make install
    $ psql dbname -c "CREATE EXTENSION index_analyzer"

And if you're on an older PostgreSQL version, you have to run the SQL
script manually (use the proper version).

    $ psql dbname < index_analyzer--0.1.sql

That's all.


License
-------
This software is distributed under the terms of BSD 2-clause license.
See LICENSE or http://www.opensource.org/licenses/bsd-license.php for
more details.