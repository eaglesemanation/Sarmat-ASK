CREATE OR REPLACE TRIGGER container_bi_e
BEFORE INSERT
ON container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  if :new.id is null then
    SELECT SEQ_cnt.nextval INTO :new.ID FROM dual;
  end if; 
END;
/
