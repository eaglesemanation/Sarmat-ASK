DROP SCHEMA IF EXISTS service;
CREATE SCHEMA service AUTHORIZATION postgres;
COMMENT ON SCHEMA service IS 'Migrated service package';

DROP SCHEMA IF EXISTS obj_robot;
CREATE SCHEMA obj_robot AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_robot IS 'Migrated obj_robot package';

DROP SCHEMA IF EXISTS obj_rpart;
CREATE SCHEMA obj_rpart AUTHORIZATION postgres;
COMMENT ON SCHEMA obj_rpart IS 'Migrated obj_rpart package';
