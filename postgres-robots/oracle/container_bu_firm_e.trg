create or replace trigger container_bu_firm_e
before update of firm_id
ON container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
     if nvl(:new.firm_id,0)<>nvl(:old.firm_id,0) and nvl(:old.firm_id,0)<>0 then
       for cc in (select * from container_content where container_id=:new.id and quantity>0) loop
         -- а не запрещена ли такая операция?
         for errr in (select * from firm_gd where firm_id=:old.firm_id and quantity_reserved>0) loop
           raise_application_error(-20123, 'Запрещено менять фирму у контейнера, по товарам которой идет отбор в настоящее время!');
         end loop;
         -- со старой фирмы убираем
         update firm_gd set quantity=quantity-cc.quantity 
         where firm_id=:old.firm_id and gd_id=cc.good_desc_id;
         -- на новую цепляем
         begin
           insert into firm_gd(firm_id, gd_id, quantity)
           values(:new.firm_id, cc.good_desc_id,cc.quantity);
         exception when others then
           update firm_gd set quantity=quantity+cc.quantity 
           where firm_id=:new.firm_id and gd_id=cc.good_desc_id;
         end;
       end loop;
       insert into command_gas(command_type_id, container_barcode, container_id, firm_id, old_firm_id)  
       values(28,:new.barcode,:new.id,:new.firm_id,:old.firm_id);
     end if;
END;
/
