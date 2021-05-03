create or replace trigger gd_party_aiu_e
after update or insert
ON gd_party
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  service.bkp_to_file('gd_party',:new.id||';'||
     :new.gd_id||';'||
     :new.pname||';'||
     :new.qty||';'||
     :new.qty_reserved||';'||
     :new.qty_doc ||';'||
     :new.id_out);

END;
/