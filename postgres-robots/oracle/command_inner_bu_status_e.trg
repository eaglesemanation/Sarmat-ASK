create or replace trigger command_inner_bu_status_e
before update of state
ON command_inner
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
BEGIN
 if :old.state=3 and :new.state=5 then -- команда успешно выполнилась
     service.log2file('  триггер command_inner_bu_status_e - команда '||:new.id||' для робота '||:new.robot_id||' успешно выполнилась'); 
     insert into tmp_cmd_inner (ci_id) values(:new.id);
     /*update command_rp 
     set 
       command_inner_last_robot_id=:new.robot_id,
       command_inner_executed=:new.id
     where id=:new.command_rp_id;*/
    :new.date_time_end:=sysdate;
    if :new.command_type_id = 8 then -- transfer
      service.mark_cell_as_full(:new.cell_dest_id, :new.container_id, :new.robot_id);
      service.mark_cell_as_free(:new.cell_src_id, :new.container_id, :new.robot_id);
    elsif :new.command_type_id = 4 then -- load
      service.mark_cell_as_free(:new.cell_src_id, :new.container_id, :new.robot_id);
      insert into tmp_cmd_inner (ci_id,action) values(:new.id,'L');      
    elsif :new.command_type_id = 5 then -- unload
      service.mark_cell_as_full(:new.cell_dest_id, :new.container_id, :new.robot_id);
      insert into tmp_cmd_inner (ci_id,action) values(:new.id,'G');      
    end if; 
 elsif :old.state=1 and :new.state=3 then -- команда успешно назначена
    :new.date_time_begin:=sysdate;
    if nvl(:new.command_rp_id,0)<>0 then
      insert into tmp_cmd_inner (ci_id,action) values(:new.id,'N');      
    end if;
-- elsif :old.state is not null and :new.state=2 then -- команда ошибка 
--     insert into tmp_cmd_inner values(:new.id);
 end if;
END;
/
