CREATE OR REPLACE FUNCTION container_bu_firm_e()
    RETURNS trigger
    LANGUAGE 'plpgsql'
    COST 100
    VOLATILE NOT LEAKPROOF
AS $BODY$
DECLARE
    cc RECORD;
    errr RECORD;
BEGIN
    IF (coalesce(NEW.firm_id, 0) <> coalesce(OLD.firm_id, 0)) AND (coalesce(OLD.firm_id, 0) <> 0) THEN
        FOR cc IN (SELECT * FROM container_content WHERE container_id = NEW.id AND quantity > 0) LOOP
            FOR errr IN (SELECT * FROM firm_gd WHERE firm_id = OLD.firm_id AND quantity_reserved > 0) LOOP
                RAISE EXCEPTION 'Запрещено менять фирму у контейнера, по товарам которой идет отбор в настоящее время!'
                    USING errcode = -20123;
            END LOOP;
            -- Remove from original firm
            UPDATE firm_gd SET quantity = quantity - cc.quantity
                WHERE firm_id = OLD.firm_id AND gd_id = cc.good_desc_id;
            -- Add to new firm
            BEGIN
                INSERT INTO firm_gd(firm_id, gd_id, quantity)
                    VALUES (NEW.firm_id, cc.good_desc_id, cc.quantity);
            EXCEPTION WHEN OTHERS THEN
                UPDATE firm_gd SET quantity = quantity + cc.quantity
                    WHERE firm_id = NEW.firm_id and gd_id = cc.good_desc_id;
            END;
        END LOOP;
        INSERT INTO command_gas (command_type_id, container_barcode, container_id, firm_id, old_firm_id)
            VALUES (28, NEW.barcode, NEW.id, NEW.firm_id, OLD.firm_id);
    END IF;
    RETURN NEW;
END;
$BODY$;

ALTER FUNCTION container_bu_firm_e()
    OWNER TO postgres;

COMMENT ON FUNCTION container_bu_firm_e()
    IS 'Checks if update of container firm is allowed';

DROP TRIGGER IF EXISTS container_bu_firm_e ON container;

CREATE TRIGGER container_bu_firm_e
    BEFORE UPDATE OF firm_id
    ON container
    FOR EACH ROW
    EXECUTE FUNCTION container_bu_firm_e();

-- vim: ft=pgsql
