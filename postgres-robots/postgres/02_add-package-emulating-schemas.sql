SET client_encoding = 'UTF8';

DROP SCHEMA IF EXISTS helpers CASCADE;
CREATE SCHEMA helpers AUTHORIZATION postgres;
COMMENT ON SCHEMA helpers IS 'Helper functions/procedures that assist migration from Oracle';

DROP SCHEMA IF EXISTS service CASCADE;
CREATE SCHEMA service AUTHORIZATION postgres;
COMMENT ON SCHEMA service IS 'Migrated service package';

DROP SCHEMA IF EXISTS trigger CASCADE;
CREATE SCHEMA trigger AUTHORIZATION postgres;
COMMENT ON SCHEMA trigger IS 'Migrated inline funtions/procedures for triggers';

DROP SCHEMA IF EXISTS obj_robot CASCADE;
CREATE SCHEMA obj_robot AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_robot IS 'Migrated obj_robot package';

DROP SCHEMA IF EXISTS obj_rpart CASCADE;
CREATE SCHEMA obj_rpart AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_rpart IS 'Migrated obj_rpart package';

DROP SCHEMA IF EXISTS obj_ask CASCADE;
CREATE SCHEMA obj_ask AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_ask IS 'Migrated obj_ask package';

DROP SCHEMA IF EXISTS obj_cmd_order CASCADE;
CREATE SCHEMA obj_cmd_order AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_cmd_order IS 'Migrated obj_cmd_order package';

DROP SCHEMA IF EXISTS obj_cmd_gas CASCADE;
CREATE SCHEMA obj_cmd_gas AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_cmd_gas IS 'Migrated obj_cmd_gas package';

DROP SCHEMA IF EXISTS obj_doc_expense CASCADE;
CREATE SCHEMA obj_doc_expense AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_doc_expense IS 'Migrated obj_doc_expense package';

DROP SCHEMA IF EXISTS extend CASCADE;
CREATE SCHEMA extend AUTHORIZATION postgres;
COMMENT ON SCHEMA extend IS 'Migrated extend package';

DROP SCHEMA IF EXISTS api CASCADE;
CREATE SCHEMA api AUTHORIZATION postgres;
COMMENT ON SCHEMA api IS 'Migrated api package';

DROP SCHEMA IF EXISTS emu CASCADE;
CREATE SCHEMA emu AUTHORIZATION postgres;
COMMENT ON SCHEMA emu IS 'Migrated emu package';
