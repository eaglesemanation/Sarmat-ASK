-- substate should be integer, not text
ALTER TABLE command_rp ALTER COLUMN substate TYPE bigint USING substate::bigint;

-- field was forgotten during migration
ALTER TABLE command_inner_checkpoint ADD COLUMN date_time_sended timestamp without time zone;
