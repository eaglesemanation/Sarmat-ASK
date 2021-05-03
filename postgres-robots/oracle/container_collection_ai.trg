create or replace trigger container_collection_ai
after insert
ON container_collection
declare
  cnt number;
BEGIN
  for tcc in (select * from tmp_cc) loop
    delete from tmp_cc where id=tcc.id;
    for cc in (select * from container_collection where id=tcc.id and state=0) loop
      select count(*) into cnt from container_collection where state=0 and container_id=cc.container_id and id<>tcc.id;
      if cnt>0 then
        raise_application_error(-20123,'Нельзя дублировать состав сборки по контейнеру!');
      end if;
    end loop;
  end loop;
END;
/
