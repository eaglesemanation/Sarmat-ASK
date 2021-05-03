create or replace package api is -- список функций API для вызова внешней ИС

  function get_cmd_gas_time_end(cg_id_ number) return date; -- получить время завершения команды перемещения контейнера
  function get_cmd_gas_time_begin(cg_id_ number) return date;  -- получить время начала команды перемещения контейнера
  function get_cmd_problem_state(cmd_id_ number) return varchar2;  -- пустышка на будущее
  function Get_Container_Last_Robot(container_id_ number, mode_ number default 3) return number; -- получить ID робота, который последний работал с указанным контейнером
  procedure get_last_cmd(comp_name_ varchar2, cmd_name out varchar2,cmd_name_full out varchar2, dt_cr out varchar2,
                         sost out varchar2, error_ out varchar2);  -- получить информацию по последней команде, поданной с указанного компьютера
  function get_problem_resolve_text(comp_name_ varchar2) return varchar2;  -- получить запрос оператору на решение проблемы


  function Calc_Min_Distance(rp_type number, max_npp number, n1 number, n2 number) return number; -- высчитать минимальное расстояние между №№ секций
  function Calc_Min_Distance(rp_id_ number, cell1_ varchar2, cell2_ varchar2) return number;  -- высчитать минимальное расстояние между ячейками 

  function Container_Accept_by_id(container_id_ number, container_barcode_ varchar2, container_type_ number, cell_id_ number, 
      priority_ number default 0) return number;  -- принять контейнер по ID
  function Container_Add(container_barcode_ varchar2, size_ number) return number; -- команда добавления нового контейнера в систему
  function Container_Transfer(repository_part_id_ number, container_barcode_ varchar2, Cell_Name_ varchar2, 
          priority_ number default 0, comp_name_ varchar2 default '') return number; -- команда перемещения контейнера
  function Container_Transfer_by_ID(container_id_ number, Cell_id_ number, priority_ number default 0) return number;  -- команда перемещения контейнера по ID
  function Container_Return(container_barcode_ varchar2) return number; -- команда возврата контейнера
  function Container_Return_by_id(container_id_ number, cell_id_ number, priority_ number default 0) return number;  -- команда возврата контейнера по ID
  function Container_Return(repository_part_id_ number, container_barcode_ varchar2, Cell_Name_ varchar2, 
     comp_name_ varchar2 default '') return number; -- команда возврата контейнера
  function Container_Remove(container_barcode_ varchar2, comp_name_ varchar2 default '') return number; -- команда извлечения контейнера из АСК
  function Container_Remove_by_id(container_id_ number) return number;  -- команда извлечения контейнера из АСК по ID

  function Problem_Resolve(comp_name_ varchar2) return number;  -- запустить процесс решения проблемы
  procedure Robot_Problem_Resolve(rid_ number, problem_resolve_id_ number, add_par_ varchar2);  -- запустить расширенный процесс решения проблемы



end api;
/
