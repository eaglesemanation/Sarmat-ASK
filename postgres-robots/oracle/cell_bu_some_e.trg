CREATE OR REPLACE TRIGGER cell_bu_some_e
BEFORE update of is_full, container_id, is_error, emp_id
ON cell
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare  
  cfchi number;
BEGIN
 if nvl(:new.is_full,0)<>nvl(:old.is_full,0) then
   select nvl(ignore_full_cell_check,0) into cfchi from repository;
   if :new.hi_level_type=999 then
       -- для ячеек приема отдельная тема 
       null;
   else
       -- для остальных 
     if cfchi=0 then
       if nvl(:new.is_full,0)<0 then
         raise_application_error(-20033,'Cell fullnes must be positive number! Cell ID='||:new.id);
       end if;
       if nvl(:new.is_full,0)>:new.max_full_size then
         raise_application_error(-20033,'Cell fullnes must be less then max_full_sixe! Cell ID='||:new.id);
       end if;
     end if;
   end if;
   if nvl(:new.is_full,0)=0 then -- освободилась
     -- а нет ли запроса на ее ошибочность?
     for cab in (select * from cell_autoblock where cell_id=:new.id and state=0 order by id) loop
       :new.is_error:=1;
       update cell_autoblock set state=1 where id=cab.id;
     end loop;
   end if;
   
   insert into log (action, comments, cell_id)
   values(30,'Cell fullness was changed from '||:old.is_full||' to '||:new.is_full,:new.id);
 end if; 
 
 if nvl(:new.is_error,0)<>nvl(:old.is_error,0) then
   insert into log (action, comments, cell_id)
   values(31,'Cell is_error was changed from '||:old.is_error||' to '||:new.is_error,:new.id);
 end if;
 
 if nvl(:new.container_id ,0)<>nvl(:old.container_id ,0) then
   insert into log (action, comments, cell_id, container_id )
   values(24,'Cell container_id was changed from '||:old.container_id ||' to '||:new.container_id ,:new.id, :new.container_id );
 end if;
 
 if nvl(:new.emp_id,0)<>nvl(:old.emp_id,0) and nvl(:new.emp_id,0)>0 then
   insert into tmp_check_cell (cell_id, action, par)
   values(:new.id, 1, :new.emp_id);
 end if;
 
END;
/
