CREATE OR REPLACE TRIGGER firm_bd_e
BEFORE delete
ON firm
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
  cnt number;
BEGIN
  select count(*) into cnt from firm_gd where firm_id=:old.id and (nvl(quantity,0)+nvl(quantity_reserved,0))>0;
  if cnt>0 then
    raise_application_error(-20123, 'Нельзя удалять клиента, по которому числятся остатки!');
  end if;
END;
/
