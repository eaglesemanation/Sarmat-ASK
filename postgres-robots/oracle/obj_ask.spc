create or replace package obj_ask is  -- пакет объекта АСК в целом

  -- типы ошибок
  error_type_robot_rp integer :=1; -- ошибка робот-подсклад
  error_type_rp       integer :=2; -- ошибка подсклад
  error_type_robot    integer :=3; -- ошибка робота
  error_type_ASK      integer :=4; -- ошибка уровня АСК

  -- типы ячеек
  CELL_TYPE_STORAGE_CELL integer:=1; -- ячейки для хранения товара
  CELL_TYPE_TRANSIT_1RP integer:=18; -- транзитные виртуальные для перемещений внутри одного подсклада
  CELL_TYPE_TR_CELL integer:=6;  -- транзитные ячейки двунаправленные
  CELL_TYPE_TR_CELL_INCOMING integer:=7;  -- транзитные ячейки входящие
  CELL_TYPE_TR_CELL_OUTCOMING integer:=8; -- транзитные ячейки исходящие


  -- функция, которая вызывается из таймера для всего склада
  procedure Form_Commands;

  -- запись строки в журнал
  procedure Log(txt_ varchar2);

  -- Is
  function Is_can_accept_cmd return number;  -- можно ли принимать команды от внешней системы?
  function Is_Cell_Locked_By_Cmd(cid number) return number;  -- не заблокирована ли ячейка командами?

  function is_enable_container_accept(rp_id_ number, cnt_id_ number) return number;  -- можно ли принять на подсклад данный контейнер?


  -- Get
  function Get_ASK_name return varchar2;  -- получить имя всего АСК
  function get_cell_name(pcell_id in number, with_notes number default 0) return varchar2;  -- получить имя ячейки
  function get_cmd_max_priority(rp_id_ number) return number;  -- берем максимальный приоритет команд на указанном подскладе
  function Get_Cnt_BC_By_ID(cnt_id_ number) return varchar2;  -- взять ШК контейера по его ID
  function Get_Cur_Max_Cmd_Priority return number;  -- берем максимальный текущий приоритет команд
  function get_good_desc_id_by_id(gdid_ varchar2) return number; -- получить числовой ID товара по символьному ID
  function Get_Desktop_Container_History(bc_ varchar2) return varchar2;  -- сформировать историю перемещений заданного контейнера
  function get_shelving_fullness(shelv_id in number) return number; -- высчитать заполненность стеллажа

  function Get_Work_Status return number;  -- получить состояние всего АСК

  
  function calc_distance(rp_type number, max_npp number, n1 number, n2 number) return number; -- вычисляет расстояние между двумя треками npp
  function calc_distance_on_way(rp_type number, max_npp number, n1 number, n2 number, dir_ in number) return number; -- вычисляем расстояние по направлению



  -- действия из C#
  procedure Change_Work_Status(new_state_ number);  -- Переключить АСК в указанный режим 
  procedure To_Pause;  -- Переключить АСК в режим <Пауза>
  procedure To_Work;  -- Переключить АСК в режим <Работает>

  -- запросы из C#
  procedure Shelving_Need_Redraw_Clear;  -- очистить список стеллажей для перерисовки
  procedure Shelving_Need_Redraw_Clear(max_id_ number);  -- очистить список стеллажей для перерисовки (но не более чем заданное ID)

  -- полезные функции
  procedure check_gdrest_consistance;  -- проверка остатков товара на консистентность
  procedure global_error_log(error_type_ number,repository_part_id_ number,robot_id_ number,errm_ varchar2);  -- добавить лог о глобальной ошибке
  procedure Set_Command(command_gas_id_ number, command_type_id_ number , 
                      rp_src_id_ number, cell_src_sname_ varchar2,  
                      rp_dest_id_ number, cell_dest_sname_ varchar2, 
                      priority_ number, container_id_ number);  -- добавить команду (таблица command) к выполнению



  -- отчеты 
  procedure Gen_Cmd_Err_Rep;  -- сформировать отчет по ошибкам команд роботов
  procedure workload_info;  -- сформировать отчет о нагрузке на АСК за последнюю неделю (отчет служебный, выводится в dbms_output)


end obj_ask;
/
