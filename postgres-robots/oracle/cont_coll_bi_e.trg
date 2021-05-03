CREATE OR REPLACE TRIGGER cont_coll_bi_e
BEFORE INSERT
ON container_collection
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 SELECT SEQ_cont_coll.nextval INTO :new.ID FROM dual;
 :new.date_time_begin :=sysdate;
 insert into tmp_cc (id, action)
 values(:new.id, 1);
END;
/
