-- substate should be integer, not text
ALTER TABLE command_rp ALTER COLUMN substate TYPE bigint USING substate::bigint;
