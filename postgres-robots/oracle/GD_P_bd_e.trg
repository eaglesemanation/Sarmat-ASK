CREATE OR REPLACE TRIGGER GD_P_bd_e
BEFORE delete
ON GD_PARTY
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  if :old.qty>0 or :old.qty_reserved>0 then
    raise_application_error (-20701, 'Нельзя удалять партии, по которым есть остаток!');
  end if;
  for cg in (select * from command_gas where gd_party_id=:old.id) loop
    raise_application_error (-20701, 'Нельзя удалять партии, по которым были команды!');
  end loop;
  for co in (select * from command_order where gd_party_id=:old.id) loop
    raise_application_error (-20701, 'Нельзя удалять партии, по которым были команды!');
  end loop;
  for dc in (select * from doc_content where gdp_id=:old.id) loop
    raise_application_error (-20701, 'Нельзя удалять партии, по которым были документы!');
  end loop;
  for сc in (select * from command_gas_container_content where gdp_id=:old.id) loop
    raise_application_error (-20701, 'Нельзя удалять партии, по которым были команды на приме товара!');
  end loop;
END;
/
