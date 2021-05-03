create or replace trigger shelving_ad_e
after delete
ON shelving
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 delete from cell where shelving_id=:old.id;
END;
/
