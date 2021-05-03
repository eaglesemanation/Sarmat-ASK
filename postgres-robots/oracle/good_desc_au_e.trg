create or replace trigger good_desc_au_e
after update
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
   if nvl(:new.quantity,0)<>nvl(:old.quantity,0) then
     insert into log (action, comments, good_desc_id, old_value, new_value)
     values(36,'Quantity was changed from '||:old.quantity||' to '||:new.quantity,:new.id,:old.quantity,:new.quantity);
   end if;
   if nvl(:new.quantity_reserved,0)<>nvl(:old.quantity_reserved,0) then
     insert into log (action, comments, good_desc_id, old_value, new_value)
     values(37,'quantity_reserved was changed from '||:old.quantity_reserved||' to '||:new.quantity_reserved,:new.id,:old.quantity_reserved,:new.quantity_reserved);
   end if;

   if nvl(:new.id,'-')<>nvl(:old.id,'-') then

     insert into log (action, comments, good_desc_id)
     values(6037,'GD.ID was changed from '||:old.ID||' to '||:new.ID,:new.id);

     update container_content cc
     set good_desc_id = :new.id
     where good_desc_id = :old.id;

 
     update firm_gd
     set gd_id=:new.id
     where gd_id = :old.id;

     update command_gas
     set good_desc_id=:new.id
     where good_desc_id is not null and good_desc_id = :old.id;

     update command_order
     set good_desc_id=:new.id
     where good_desc_id is not null and good_desc_id = :old.id;

     update command_gas_container_content
     set gd_id=:new.id
     where gd_id is not null and gd_id = :old.id;


   end if;
END;
/
