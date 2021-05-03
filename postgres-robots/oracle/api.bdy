create or replace package body api is


-- получить информацию по последней команде, поданной с указанного компьютера
procedure get_last_cmd(comp_name_ varchar2, cmd_name out varchar2,cmd_name_full out varchar2, dt_cr out varchar2,
                       sost out varchar2, error_ out varchar2) is
begin
  service.get_last_cmd(comp_name_ , cmd_name ,cmd_name_full , dt_cr ,
                       sost , error_ );
end;


-- получить запрос оператору на решение проблемы
function get_problem_resolve_text(comp_name_ varchar2) return varchar2 is
begin
  return obj_robot.get_problem_resolve_text(comp_name_);
end;

-- запустить процесс решения проблемы
function Problem_Resolve(comp_name_ varchar2) return number is
begin
  return obj_robot.Problem_Resolve(comp_name_);
end;

-- высчитать минимальное расстояние между №№ секций
function Calc_Min_Distance(rp_type number, max_npp number, n1 number, n2 number) return number is
begin
  return obj_rpart.Calc_Min_Distance(rp_type , max_npp , n1 , n2 );
end;

-- высчитать минимальное расстояние между ячейками 
function Calc_Min_Distance(rp_id_ number, cell1_ varchar2, cell2_ varchar2) return number is
begin
  return obj_rpart.Calc_Min_Distance(rp_id_ , cell1_ , cell2_ );
end;

-- пустышка на будущее
function get_cmd_problem_state(cmd_id_ number) return varchar2 is
begin
  return '';
end;

-- команда перемещения контейнера
function Container_Transfer(repository_part_id_ number, container_barcode_ varchar2, Cell_Name_ varchar2, priority_ number default 0, comp_name_ varchar2 default '') return number is
  id_ number;
begin
  insert into command_gas (command_type_id, rp_id, container_barcode , Cell_Name , comp_name, priority)
  values(14,repository_part_id_,container_barcode_ , Cell_Name_ , comp_name_, priority_)
  returning id into id_;
  return id_;
end;

-- команда перемещения контейнера по ID
function Container_Transfer_by_ID(container_id_ number, Cell_id_ number, priority_ number default 0) return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_id, cell_id, priority )
  values(14,container_id_ , Cell_id_ ,priority_)
  returning id into id_;
  return id_;
end;


-- команда возврата контейнера
function Container_Return(repository_part_id_ number, container_barcode_ varchar2, Cell_Name_ varchar2, comp_name_ varchar2 default '') return number is
  id_ number;
begin
  insert into command_gas (command_type_id, rp_id, container_barcode , Cell_Name , comp_name)
  values(18,repository_part_id_,container_barcode_ , Cell_Name_ , comp_name_)
  returning id into id_;
  return id_;
end;

-- команда возврата контейнера
function Container_Return(container_barcode_ varchar2) return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_barcode)
  values(18,container_barcode_ )
  returning id into id_;
  return id_;
end;

-- команда возврата контейнера по ID
function Container_Return_by_id(container_id_ number, cell_id_ number, priority_ number default 0) return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_id, cell_id, priority)
  values(18,container_id_, cell_id_, priority_)
  returning id into id_;
  return id_;
end;

-- принять контейнер по ID
function Container_Accept_by_id(container_id_ number, container_barcode_ varchar2, container_type_ number, cell_id_ number, priority_ number default 0) return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_id, container_barcode, container_type, cell_id, priority)
  values(11,container_id_, container_barcode_, container_type_,cell_id_,priority_)
  returning id into id_;
  return id_;
end;


-- команда извлечения контейнера из АСК
function Container_Remove(container_barcode_ varchar2, comp_name_ varchar2 default '') return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_barcode , comp_name)
  values(13,container_barcode_ , comp_name_)
  returning id into id_;
  return id_;
end;

-- команда извлечения контейнера из АСК по ID
function Container_Remove_by_id(container_id_ number) return number is
  id_ number;
begin
  insert into command_gas (command_type_id, container_id)
  values(13,container_id_)
  returning id into id_;
  return id_;
end;

-- команда добавления нового контейнера в систему
function Container_Add(container_barcode_ varchar2, size_ number) return number is
  id_ number;
begin
  insert into container (barcode, type )
  values(container_barcode_,size_)
  returning id into id_;
  return id_;
end;

-- запустить расширенный процесс решения проблемы
procedure Robot_Problem_Resolve(rid_ number, problem_resolve_id_ number, add_par_ varchar2) is
begin
  for rr in (select * from robot where id=rid_ and nvl(command_inner_id,0)>0) loop
    for ci in (select * from command_inner where id=rr.command_inner_id) loop
      for pr in (select * from problem_resolving pr
                 where command_type_id=ci.command_type_id and rr.platform_busy=nvl(platform_busy,rr.platform_busy) and id=problem_resolve_id_) loop
       update command_inner set problem_resolving_id=problem_resolve_id_, problem_resolving_par =add_par_ where id=rr.command_inner_id;
       commit;
       return;
     end loop;
     raise_application_error (-20012, 'Выбран неверный вариант решения проблемы!');
    end loop;
  end loop;
  raise_application_error (-20012, 'Нет возможности решить проблему для робота без команды!');
end;

-- получить время начала команды перемещения контейнера
function get_cmd_gas_time_begin(cg_id_ number) return date is
begin
  for cmd in (select * from command where command_gas_id=cg_id_ order by date_time_begin) loop
    return cmd.date_time_begin;
  end loop;
  return null;
end;

-- получить время завершения команды перемещения контейнера
function get_cmd_gas_time_end(cg_id_ number) return date is
begin
  for cmd in (select * from command where command_gas_id=cg_id_ order by date_time_end desc) loop
    return cmd.date_time_end;
  end loop;
  return null;
end;

-- получить ID робота, который последний работал с указанным контейнером
function Get_Container_Last_Robot(container_id_ number, mode_ number default 3) return number is
begin
  if mode_=1 then
    for ci in (select * from command_inner where container_id=container_id_ order by id desc)  loop
      return ci.robot_id;
    end loop;
  elsif mode_=2 then
    for ci in (select * from command_inner where container_id=container_id_ and state=5 and date_time_end is not null order by id desc)  loop
      return ci.robot_id;
    end loop;
  elsif mode_=3 then
    for ci in (select ci.robot_id from command_inner ci, command_rp crp 
               where ci.container_id=container_id_ and ci.state=5 and command_rp_id=crp.id and crp.state=5
               order by ci.id desc)  loop
      return ci.robot_id;
    end loop;
  end if;
  return null;
end;


end api;
/
