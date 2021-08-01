SET client_encoding = 'UTF8';

DROP EXTENSION IF EXISTS adminpack;
CREATE EXTENSION adminpack
    SCHEMA pg_catalog
    VERSION "1.1";

DROP EXTENSION IF EXISTS plpgsql_check;
CREATE EXTENSION plpgsql_check
    SCHEMA pg_catalog
    VERSION "1.17";
