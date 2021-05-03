create or replace trigger command_rp_ad_e
after delete
ON command_rp
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 delete from command_inner where command_rp_id=:old.id;
 update robot set command_rp_id=null where command_rp_id=:old.id;
end;
/
