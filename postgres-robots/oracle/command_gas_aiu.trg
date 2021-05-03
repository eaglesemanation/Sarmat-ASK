create or replace trigger command_gas_aiu
after update or insert
ON command_gas
declare
  qq number;
BEGIN
  -- прием товара
  for tg in (select * from tmp_cmd_gas where action=1) loop
    delete from tmp_cmd_gas where cmd_gas_id=tg.cmd_gas_id;
    for cg in (select * from command_gas where id=tg.cmd_gas_id) loop
      qq:=obj_doc_expense.get_pridoc_rest(cg.pri_doc_number);
      if qq=0 then
        update doc set accepted=3 where accepted=1 and id=cg.pri_doc_number;
      end if;
    end loop;
  end loop;

  -- отбор товара
  for tg in (select * from tmp_cmd_gas where action=3) loop
    delete from tmp_cmd_gas where cmd_gas_id=tg.cmd_gas_id;
    for cg in (select * from command_gas where id=tg.cmd_gas_id) loop
      qq:=obj_cmd_order.get_rasdoc_rest(cg.pri_doc_number);
      if qq=0 then
        update doc set accepted=3 where accepted=1 and id=cg.pri_doc_number;
      end if;
    end loop;
  end loop;
  
  if inserting then
    for rr in (select * from repository where nvl(CYCLE_CHECK_GDREST_CONSISTANCE,0)=1) loop
      obj_ask.check_gdrest_consistance;
    end loop;
  end if;

END;
/
