CREATE OR REPLACE TRIGGER good_desc_bi_e
BEFORE INSERT
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 SELECT SEQ_good_desc.nextval INTO :new.GOOD_DESC_ID FROM dual;
 if :new.ID is null then
   SELECT -SEQ_gd_id.nextval INTO :new.ID FROM dual;
   --:new.id:=-1;
 end if;
 if :new.name is null then
   :new.name:='-' || abs(:new.ID);
 end if;
 
END;
/
