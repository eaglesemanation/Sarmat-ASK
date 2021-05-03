CREATE OR REPLACE TRIGGER repository_bu_work_e
BEFORE update of is_work
ON repository
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW

BEGIN
  if :old.is_work=0 and :new.is_work=1 then -- нужна проверка
    null;
  end if;
END;
/
