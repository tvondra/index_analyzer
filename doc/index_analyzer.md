index_analyzer
==============

Synopsis
--------

    Functions for analysis of indexes - existing or considered.


Description
-----------

A package that might help you if you need to evaluate the existing
or considered indexes. So these functions may be useful for you if
you need to know which indexes are not used at all (thus slowing
down modifications and occupy space on the drive but not helping
the queries) or might be useful if created.


Usage
-----

All the main functions return a table listing indexes that are
considered inefficient / unused. The table has these columns:

    * **relname** - name of the relation
    * **idxname** - name of the index
    * **reason**  - short explanation why the index was added
    * **selectivity** - estimated selectivity of the index
    * **ndistinct**  - number of distinct values in the index
    * **nrows** - number of rows in the index
    * **npages** - number of pages occupied by the index

To use the functions, just execute them as any other set-returning
function. For example to check all indexes in schema 'public', using
a 5% selectivity threshold, do:

    SELECT * FROM analyze_tables('public', 5.0)

To check only a single table, called 'my_table', try this:

    SELECT * FROM analyze_table('my_table'::regclass, 5.0)

And to check index 'my_index', do

    SELECT * FROM analyze_index('my_index'::regclass, 5.0)

Similarly for the other `analyze\_index\_%` functions.


The functions for foreign keys analysis are pretty straightforward
to use too - most of the time you'll analyze either all foreign keys
on all tables in a given schema:

    SELECT * FROM analyze_fks('public')

or on a particular table - e.g. called 'my_table'

    SELECT * FROM analyze_fks('my_table'::regclass)

There's also a function `analyze_fk(OID)` for analysis of one foreign
key called 'my_fk' you can do this

    SELECT * FROM analyze_fk('my_fk')

And that's all.


Support
-------

This extension is hosted on github, including bug tracker and so on:

    https://github.com/tvondra/index_analyzer

You may also contact me directly at tv@fuzzy.cz.


Author
------

Tomas Vondra <tv@fuzzy.cz>


Copyright and License
---------------------

This software is distributed under the terms of BSD 2-clause license.
See LICENSE or http://www.opensource.org/licenses/bsd-license.php for
more details.
