CREATE OR REPLACE TRIGGER firm_gd_bu_qty_e
BEFORE update of quantity, quantity_reserved
ON firm_gd
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 update good_desc 
 set 
   quantity=quantity+(:new.quantity - :old.quantity),
   quantity_reserved=quantity_reserved+(:new.quantity_reserved - :old.quantity_reserved)
 where id=:new.gd_id;
END;
/
