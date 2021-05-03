create or replace trigger GOOD_DESC_biu_e
before update or insert
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  if nvl(:new.quantity_box,0)=0 then
    :new.quantity_box:=1;
  end if;
  if nvl(:new.cubage,0)=0 then
    :new.cubage:=1;
  end if;
  if trim(:new.id)<>:new.id then
    :new.id:=trim(:new.id);
  end if;
  if instr(:new.id,';')<>0 then
    raise_application_error(-20070,'Символ <;> нельзя использовать в коде товара!');
  end if;

  if inserting or updating and nvl(:new.id,'0')<>nvl(:old.id,'0') then
    :new.id_upper:=upper(:new.id);
  end if;
  
END;
/
