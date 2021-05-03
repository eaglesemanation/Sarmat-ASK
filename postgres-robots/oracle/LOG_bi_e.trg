CREATE OR REPLACE TRIGGER LOG_bi_e
 BEFORE
 INSERT
 ON LOG
 REFERENCING OLD AS OLD NEW AS NEW
 FOR EACH ROW
begin
 :new.date_time:=sysdate();
 :new.date_time_stamp:=systimestamp;
 :new.user_name:=user();
 :new.ms:=round(to_number(to_char(systimestamp,'FF'))/1000000); 
end LOG_bi_e;
/
