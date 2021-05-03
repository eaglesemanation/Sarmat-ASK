create or replace trigger command_gas_ad_e
after delete
ON command_gas
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 service.log2file('удаление command_gas с id='||:old.id);
 delete from command where command_gas_id =:old.id;
 delete from command_gas_cell_in  where command_gas_id =:old.id;
 delete from command_gas_out_container   where cmd_gas_id =:old.id;
 delete from command_gas_out_container_plan    where cmd_gas_id =:old.id;
 delete from container_collection where cmd_gas_id =:old.id;
 
end;
/
