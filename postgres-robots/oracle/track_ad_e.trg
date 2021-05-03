create or replace trigger track_ad_e
after delete
ON track
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
 delete from shelving where track_id=:old.id;
END;
/
