create or replace trigger container_aui_some_e
after update of location,
cell_id,
robot_id,
cell_goal_id
or insert
ON container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 if inserting then
     insert into log (action, comments, container_id)
     values(29,'Container added with barcode='||:new.barcode,:new.id);
 end if;

 if updating then
   if nvl(:new.location,0)<>nvl(:old.location,0) then
     insert into log (action, comments, container_id)
     values(25,'Container location was changed from '||:old.location||' to '||:new.location,:new.id);
   end if;
   if nvl(:new.barcode,'-')<>nvl(:old.barcode,'-') then
     insert into log (action, comments, container_id)
     values(29,'Container barcode was changed from '||:old.barcode||' to '||:new.barcode,:new.id);
   end if;
   if nvl(:new.cell_id,0)<>nvl(:old.cell_id,0) then
     insert into log (action, comments, container_id, cell_id)
     values(27,'Container cell_id was changed from '||:old.cell_id||' to '||:new.cell_id,:new.id,:new.cell_id);
   end if;
   if nvl(:new.cell_goal_id ,0)<>nvl(:old.cell_goal_id ,0) then
     insert into log (action, comments, container_id, cell_id)
     values(28,'Container cell_goal_id  was changed from '||:old.cell_goal_id ||' to '||:new.cell_goal_id ,:new.id,:new.cell_goal_id );
   end if;
   if nvl(:new.robot_id,0)<>nvl(:old.robot_id,0) then
     insert into log (action, comments, container_id, robot_id)
     values(26,'Container robot_id was changed from '||:old.robot_id||' to '||:new.robot_id,:new.id,:new.robot_id);
   end if;
 end if;
END;
/
