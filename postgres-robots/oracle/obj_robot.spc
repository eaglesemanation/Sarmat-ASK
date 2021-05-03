create or replace package obj_robot is -- пакет для объекта "Робот"

  -- DIR:
  DIR_CW number:=1; -- по часовой, от меньшего к большему
  DIR_CCW number:=0; -- против часовой, от большего к меньшему
  DIR_NONE number:=-1; -- нет никакого направления

  -- символьные названия команд
  CMD_LOAD varchar2(10):='LOAD';
  CMD_UNLOAD varchar2(10):='UNLOAD';
  CMD_MOVE varchar2(10):='MOVE';
  CMD_INITY varchar2(10):='INITY';

  -- числовые коды команд
  CMD_LOAD_TYPE_ID number:=4; -- LOAD
  CMD_UNLOAD_TYPE_ID number:=5;  -- UNLOAD
  CMD_MOVE_TYPE_ID number:=6;  -- MOVE
  CMD_INITY_TYPE_ID number:=32; --  INITY

  -- состояния робота
  ROBOT_STATE_READY number:=0; -- готов
  ROBOT_STATE_BUSY number:=1;  -- работает
  ROBOT_STATE_ERROR number:=2;  -- в ошибке
  ROBOT_STATE_INIT number:=3;  -- в режиме инициализации
  ROBOT_STATE_REPAIR number:=6;  -- в починке
  ROBOT_STATE_DISCONNECT number:=8;  -- нет связи

  -- варианты решения проблема
  PR_UNLOAD_RETRY number:=5; -- повторить команду UNLOAD
  PR_UNLOAD_HANDLE number:=6; -- UNLOAD выполнена вручную
  PR_UNLOAD_MARK_BAD_REDIRECT number:=14; -- UNLOAD - пометить целевую ячейку как плохую и перенаправить контейнер в другую ячейку
  PR_UNLOAD_INDICATE_REDIRECT number:=15; -- UNLOAD - Указать какой контейнер находится в ячейке и перенаправить текущий контейнер в другую ячейку
  PR_LOAD_RETRY number:=1; -- повторить LOAD
  PR_LOAD_HANDLE number:=2; -- LOAD выполнена вручную
  PR_LOAD_CELL_EMPTY number:=16;  -- LOAD - целевая ячейка пуста
  PR_LOAD_CELL_BAD number:=18;  -- LOAD - Контейнер в целевой ячейке заклинило

  -- процедура ведения журнала
  procedure Log(robot_id_ number, txt_ varchar2);

  -- IS робот готов для новых команд?
  function Is_Robot_Ready_For_Cmd(rid_ number, not_connected_is_ready_ boolean default false) return number; -- робот готов для команд перемещения контейнера?
  function Is_Robot_Ready_For_Cmd_Inner(rid_ number) return number; -- робот готов для подкоманд перемещения контейнера (load/unload)?

  -- Общие Get-команды
  function get_ci_cnt_bc(rid_ number) return varchar2;  -- взять ШК контейнера команды перемещения контейнера по id роботу
  function get_ci_cell_src(rid_ number) return varchar2;  -- взять имя ячейки источника команды робота по id роботу
  function get_ci_cell_dst(rid_ number) return varchar2;  -- взять имя ячейки назначения команды робота по id роботу
  function Get_Cmd_Cell_Src(rid_ number) return varchar2; -- получить имя ячейки-источника для команды перемещения контейнера по ID робота
  function Get_Cmd_Cell_Dest(rid_ number) return varchar2;  -- получить имя ячейки назначения для команды перемещения контейнера по ID робота
  function Get_Cmd_Container(rid_ number) return varchar2;  -- получить ШК контейнера команды перемещения контейнера по ID робота
  function Get_Cmd_Dir(rid_ number, nnm_ number default 1) return number;  -- получить направление команды перемещения контейнера по ID робота (доп. параметр - часть команды)
  function Get_Cmd_Inner_Checkpoint(cmd_inner_id_ number) return varchar2; -- возвращает ID и NPP промежуточной точки команды, или -1 если нет такой
  function Get_Cmd_Inner_CP_Process(cmd_inner_id_ number) return varchar2; -- возвращает строку лога работы с промежуточными точками по команде
  function get_cmd_inner_dtb(cid_ number) return date;  -- получить дату-время начала команды робота по ID
  function Get_Cmd_Inner_Imi_Type(cid_ number) return number; -- получить тип команда для имитационного моделирования (с учетом перемещений попромежуточным точкам)
  function Get_Cmd_Inner_Last_Checkpoint(cmd_inner_id_ number, in_status_ number default null) return number; -- возвращает NPP последней промежуточной точки команды, или -1 если нет такой
  function Get_Cmd_Inner_Npp_Dest(cid_ number, is_use_cp_ number default 0) return number;  -- получить № целевого трека команды робота
  function Get_Cmd_Inner_Time_Work(cid_ number) return number;  -- получить сколько времени в секундах уже работает команда работа (но не более 6 минут)
  function Get_Cmd_Inner_Txt(rid_ number) return varchar2;  -- получить текст команды робота по ID робота
  function Get_Cmd_Inner_Type(rid_ number) return number;  -- получить тип команды робота по ID робота
  function get_cmd_robot_name(cmd_id_ number) return varchar2;  -- возвращает робота, который делал команду перемещения контейнеров
  function get_cmd_text_another_dir(ct varchar2) return varchar2;  -- возвращает текст команды робота с иным направлением движения по/против часовой стрелке
  function Get_Cmd_Text_New_cp(ct_ varchar2, new_cp_ number) return varchar2; -- заменяет 'cp=NNN' в тексте команды на другую секцию
  function Get_Cmd_Text_WO_cp(ct_ varchar2) return varchar2; -- исключает 'cp=NNN' из текста команды
  function Get_Robot_Name(rid_ number) return varchar2;  -- получить имя робота по его ID для отчета
  function Get_Robot_RP_ID(rid_ number) return number;  -- получить подсклад робота по ID робота
  function Get_Robot_RP_name(rid_ number) return varchar2;  -- получить имя подсклада робота по ID робота
  function Get_Robot_State(rid_ number) return number;  -- получить состояние робота по его ID


  -- решение проблем из внешней системы
  function get_problem_resolve_text(comp_name_ varchar2) return varchar2;
  function Get_robot_problem_resolve_cs(rid_ number) return varchar2;
  function get_last_comp_ci(comp_name_ varchar2) return number;

  -- починка
  function set_mode_to_repair(rid_ number, npp_rep number, param number) return varchar2;  -- перевести робота в режим починки
  function set_repair_done(rid_ number) return varchar2;  -- выйти из режима починки робота в нормальный рабочий режим
  function get_repair_stop_param(rid_ number) return number;  -- получение информации о дополнительных параметрах для перевода робота в режим почники по ID робота

  -- вызываются из C#
  procedure Change_only_move_status(rid_ number);  -- сменить у робота режим "Only Move"
  procedure Info_From_Sarmat(rid_ number, rez_ in varchar2);  -- доклад SQL серверу о состоянии робота с Sarmat
  procedure Mark_Cmd_Inner_Send_To_Robot(robot_id_ in number, cmd_inner_id_ in number); -- отмечаем, что команда успешно отдана роботу на исполнение
  procedure Mark_CI_CP_Send_To_Robot (cpcg_id_ number, new_status_ number default 1); -- пометить промежуточные точки как посланные роботу

  procedure Set_CmdRP(crp_ID_ number, Robot_ID_ number, Dir1_ number, Dir2_ number, Calc_Cost_ number, Pri_Inner_ number);  -- назначает команду на SQL сервере на робота с оптимизатора Sarmat

  -- пришло решение проблемы
  procedure change_cmd_unload_goal(cmd_inner_id_ number, new_cell_goal_id_ number);  -- изменить целевую ячейку команды для робота (Unload)
  procedure change_wpr_dir(ci_id_ number, new_dir_ number);  -- изменить направление команды робота на противоположное
  function Problem_Resolve(rid_ number, cit_ number, pb_ number, pr_id_ number, ans_ varchar2 default '') return number;  -- решение проблемы команды сложное, с параметрами
  function Problem_Resolve(comp_name_ varchar2) return number;  -- решение с компьютера оператора  простое
  procedure Redirect_Robot_To_New_Cell(robot_id_ number, cmd_rp_id_ number, 
      container_id_ number, ci_npp_dest_ number, ci_cell_dest_id_ number);  -- перенаправить робота в новую целевую ячейку (Unload)

  -- вызываются из obj_rpart
  procedure InitY_If_Ness(rid_ number);  -- даем команду роботу INITY, если нужно
  procedure Set_Command_Inner(robot_id_ in number,
                      crp_id_ in number,
                      new_cmd_state_ in number,
                      cmd_inner_type_ in number,
                      dir_ in number,
                      cell_src_sname_ in varchar2,
                      cell_dest_sname_ in varchar2,
                      cmd_text_ in varchar2,
                      container_id_ in number default 0,
                      check_point_ number default null); -- выдаем роботу простую команду типа load/Unload/Move

  -- просто полезные функции
  procedure Cmd_RP_Cancel(robot_id_ number);  -- снимает назначенную команду с робота, если еще процесс не пошел





end obj_robot;
/
