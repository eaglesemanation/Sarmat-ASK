CREATE OR REPLACE TRIGGER gd_party_bu_qty_e
BEFORE update of qty, qty_reserved
ON gd_party
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 update good_desc
 set
   quantity=quantity+(:new.qty - :old.qty),
   quantity_reserved=quantity_reserved+(:new.qty_reserved - :old.qty_reserved)
 where good_desc_id=:new.gd_id;
 service.log2file('  gd_party_bu_qty_e id='||:new.id||' :new.qty='||:new.qty||' :old.qty='||:old.qty||' :new.qty_doc='||:new.qty_doc);
 if :new.qty > :old.qty then
    :new.qty_doc:= :old.qty_doc+(:new.qty - :old.qty);
 end if;
END;
/
