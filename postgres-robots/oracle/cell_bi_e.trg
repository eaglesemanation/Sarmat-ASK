CREATE OR REPLACE TRIGGER cell_bi_e
BEFORE INSERT
ON cell
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 if :new.id is null then 
   SELECT SEQ_cell.nextval INTO :new.ID FROM dual;
 end if;
END;
/
