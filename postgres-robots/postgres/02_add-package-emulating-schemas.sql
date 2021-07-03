DROP SCHEMA IF EXISTS helpers;
CREATE SCHEMA helpers AUTHORIZATION postgres;
COMMENT ON SCHEMA helpers IS 'Helper functions/procedures that assist migration from Oracle';

DROP SCHEMA IF EXISTS service;
CREATE SCHEMA service AUTHORIZATION postgres;
COMMENT ON SCHEMA service IS 'Migrated service package';

DROP SCHEMA IF EXISTS trigger;
CREATE SCHEMA trigger AUTHORIZATION postgres;
COMMENT ON SCHEMA trigger IS 'Migrated inline funtions/procedures for triggers';

DROP SCHEMA IF EXISTS obj_robot;
CREATE SCHEMA obj_robot AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_robot IS 'Migrated obj_robot package';

DROP SCHEMA IF EXISTS obj_rpart;
CREATE SCHEMA obj_rpart AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_rpart IS 'Migrated obj_rpart package';

DROP SCHEMA IF EXISTS obj_ask;
CREATE SCHEMA obj_ask AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_ask IS 'Migrated obj_ask package';
