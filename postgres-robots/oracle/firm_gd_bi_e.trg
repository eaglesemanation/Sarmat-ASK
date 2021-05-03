CREATE OR REPLACE TRIGGER firm_gd_bi_e
BEFORE INSERT
ON firm_gd
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 if :new.ID is null then
   SELECT SEQ_fgd.nextval INTO :new.ID FROM dual;
 end if;
 update good_desc set quantity=quantity+:new.quantity 
 where id=:new.gd_id;
END;
/
