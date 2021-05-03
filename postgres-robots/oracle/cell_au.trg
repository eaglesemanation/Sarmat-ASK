create or replace trigger cell_au
after update
ON cell
declare
  cnt number;
BEGIN
  for tmp in (select * from tmp_check_cell where action=1)  loop
    delete from tmp_check_cell where cell_id=tmp.cell_id;
    select count (distinct (repository_part_id)) into cnt 
    from cell where emp_id=tmp.par;
    if cnt>1 then
      raise_application_error(-20123, 'Для одного сотрудника возможны ячейки лишь на одном складе!');
    end if;
  end loop;
END;
/
