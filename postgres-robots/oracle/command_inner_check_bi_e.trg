CREATE OR REPLACE TRIGGER command_inner_check_bi_e
BEFORE INSERT
ON command_inner_checkpoint
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 --:new.user_name:=user;

 if :new.ID is null then
   SELECT SEQ_cich.nextval INTO :new.ID FROM dual;
   :new.date_time_create:=sysdate;
   --:new.command_to_run:=:new.command_to_run||';'||:new.id;
 end if;
END;
/
