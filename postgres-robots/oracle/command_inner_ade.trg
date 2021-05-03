create or replace trigger command_inner_ade
after delete
ON command_inner
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
BEGIN
  for rr in (select * from robot where :old.id in (nvl(command_inner_assigned_id,0),nvl(command_inner_id,0))) loop
    update robot set state=0, wait_for_problem_resolve =0 , command_inner_id=0, command_inner_assigned_id =0
    where id=rr.id;
  end loop;
END;
/
