CREATE OR REPLACE TRIGGER good_desc_bd_e
BEFORE delete
ON good_desc
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  if :old.quantity>0 or :old.quantity_reserved>0 then
    raise_application_error(-20123, service.ml_get_rus_eng_val('Нельзя удалять товар, по которому числится ненулевое кол-во!',
            'It is impossible to remove the goods on which the non-zero quantity is registered!'));
  end if;
  for dc in (select * from doc_content where good_id=:old.good_desc_id) loop
    raise_application_error(-20123, service.ml_get_rus_eng_val('Нельзя удалять товар, по которому есть состав документов!',
       'It is impossible to remove the goods on which there is a structure of documents!'));
  end loop;
END;
/
