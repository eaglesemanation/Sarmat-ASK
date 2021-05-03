create or replace trigger rp_ad_e
after delete
ON repository_part
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 delete from track where repository_part_id=:old.id;
 --delete from cell where repository_part_id=:old.id;
 delete from robot where repository_part_id=:old.id;
 --delete from shelving where repository_part_id=:old.id;
END;
/
