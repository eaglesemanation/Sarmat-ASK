-- substate should be integer, not text
ALTER TABLE command_rp ALTER COLUMN substate TYPE bigint USING substate::bigint;

-- id should be integer, not text
-- but there are multiple occurrences of mistyped id and it's easier
--   to typecast in place instead of fixing it
-- ALTER TABLE good_desc ALTER COLUMN id TYPE bigint USING id::bigint;
