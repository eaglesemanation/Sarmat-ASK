create or replace trigger container_aiu_e
after update or insert
ON container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  service.bkp_to_file('container',:new.id||';'||
     :new.barcode||';'||
     :new.type||';'||
     :new.location||';'||
     :new.cell_id||';'||
     :new.robot_id||';'||
     :new.cell_goal_id||';'||
     :new.firm_id);
END;
/
