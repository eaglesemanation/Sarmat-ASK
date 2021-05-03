create or replace trigger command_ad_e
after delete
ON command
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 delete from command_rp where command_id=:old.id;
 delete from cell_cmd_lock where cmd_id=:old.id;
end;
/
