CREATE OR REPLACE FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"(
	)
    RETURNS bigint
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE PARALLEL UNSAFE
AS $BODY$
BEGIN
    RETURN 18;
END;
$BODY$;
ALTER FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"() OWNER TO postgres;
COMMENT ON FUNCTION obj_ask."CELL_TYPE_TRANSIT_1RP"()
    IS 'Emulating package variable. Virtual cell for inner warehouse transfers.
Тип ячейки: транзитные виртуальные для перемещений внутри одного подсклада';

-- vim: ft=pgsql
