create or replace trigger GOOD_DESC_aiu_e
after update or insert
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  service.bkp_to_file('good_desc',:new.id||';'||
     :new.name||';'||
     :new.abc_rang ||';'||
     :new.quantity||';'||
     :new.quantity_reserved);

END;
/
