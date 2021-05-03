CREATE OR REPLACE TRIGGER good_desc_ad_e
after delete
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  delete from container_content 
  where good_desc_id=:old.id;
  delete from firm_gd 
  where gd_id=:old.id;
END;
/
