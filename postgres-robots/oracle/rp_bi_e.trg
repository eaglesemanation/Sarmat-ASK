CREATE OR REPLACE TRIGGER rp_bi_e
BEFORE INSERT
ON repository_part
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 if :new.id is null then 
   SELECT SEQ_rp.nextval INTO :new.ID FROM dual;
 end if;
END;
/
