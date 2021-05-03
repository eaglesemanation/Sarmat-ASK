CREATE OR REPLACE TRIGGER command_gas_bu_state_e
BEFORE update of state
ON command_gas
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
BEGIN
 :new.state_ind:=:new.state;
 if :new.state<>:old.state then
   if :new.state=1 then
     :new.date_time_begin:=sysdate;
   end if;
   if :new.state=5 then
     :new.date_time_end:=sysdate;
   end if;
 end if;
 --------------------------
 -- Good.Out
 --------------------------
 if :new.COMMAND_TYPE_ID=12 then
   -- назначены все команды
   if :new.state=3 then
     update command_order
     set state=3
     where command_gas_id=:new.id and state<3;
/*   -- все подвезено
   elsif :new.state=5 then
     update command_order
     set state=5
     where command_gas_id=:new.id;*/
   end if;
 end if;
END;
/
