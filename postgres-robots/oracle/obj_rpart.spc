create or replace package obj_rpart is -- объект подсклада (огурца)

  -- занести строку в Лог
  procedure Log(rp_id_ number, txt_ varchar2);

  -- основная функция, которая вызывается из фоновой процедуры C# бесконечного цикла
  procedure Form_Cmds(rpid_ number);

  -- тестируем механизм работы
  procedure crash_test_tact(rpid_ number); -- такт теста по подскладу
  procedure crash_test_rzn; -- тест для Рязани

  -- IS
  function Is_Active_Command_RP(rpid_ number) return number;  -- есть ли активные команды перемещения контейнеров на огурце?
  function is_cell_cmd_track_lock(cell_id_ number) return number; -- заблокирован ли трек через команду по ячейке cell_cmd_lock !!!!
  function is_cell_locked_by_repaire(cell_id_ number) return number; -- заблокирована ли ячейка роботом в состоянии починки?
  function is_exists_cell_type(rp_id_ number, ct_ number) return number; -- есть ли неошибочные ячейки указанного подтипа на складе?
  function is_idle(rp_id_ number) return number; -- простаивает ли АСК без команд?
  function Is_Npp_Actual_Info(rp_id_ number) return number; -- акутальна ли информация в АСК по расположению роботов?
  function is_poss_to_lock(robot_id_ in number, track_npp_dest in number, direction_ in number,  -- определяет, возможно ли заблокировать путь
                     crp_id_ in number default 0) return number;

  function is_poss_ass_new_unload_cell(old_cell_id number, robot_id_ number) return number; -- можно ли найти ячейку вместо ошибочной?
  function is_robot_lock_bad(rid_ number) return number; -- плохая блокировка робота
  function is_rp_simple_1_robot(rp_id_ number) return number;  -- является ли огурец простым с одним роботом?
  function is_track_between(goal_npp in number,npp_from in number,npp_to in number,dir in number, rp_id_ in number) return number; -- указанный трек между двумя треками по направлению?
  function is_track_locked(robot_id_ in number, npp_d number, dir number, 
     maybe_locked_ number default 0, check_ask_1_robot number default 0) return number;  -- интеллектуальная функция определения - заблокирован ли трек? (учитывает шлейф робота)
  function Is_Track_Locked_Around(rid_ number, npp_ number, maybe_locked_ number default 0) return number;  -- заблокировано ли вокруг? (если maybe_locked_==1, то еще и нет ли помех для блокировки если нужно?)
  function Is_Track_Near_Repair_Robot(rp_id_ number, npp_ number) return number; -- находится ли трек в шлейфе поломанного робота?
  function is_track_npp_BAN_MOVE_TO(rp_id_ number, npp_ number) return number;  -- является ли трек запрещенным для команд Move туда?
  function Is_Track_Part_Between(to_id_ number, npp_from number,  npp_to number,  dir number) return boolean; -- является ли указанная заявка на блокировку между указанными треками по заданному направлению?
  function is_way_free(robot_id_ in number, npp_d number, dir number) return number; -- проверка на свободность пути
  function is_way_locked(rp_id_ in number, robot_id_ in number, goal_npp in number) return number; -- заблокирован ли путь для робота до цели?

  function has_free_cell(csize in number, rp_id_ number default 0) return number; -- есть ли свободное место ?
  function has_free_cell_by_cnt(cntid in number, rp_id_ number default 0) return number;  -- есть ли свободное место для контейнера заданного размера?

  -- Calc
  function add_track_npp(rp_id_ number, npp_from_ number,npp_num_ number, dir_ number) return number;  -- примитив для добавления к номеру трека столько-то секций
  function Calc_Distance_By_Dir(rpid_ number, n1 number, n2 number, dir_ number) return number;  -- вычисляет расстояние между двумя треками npp по указанному направлению
  function Calc_Min_Distance(rp_id_ number, cell1_ varchar2, cell2_ varchar2) return number; -- вычисляет расстояние между двумя ячейками по оптимальному направлению 
  function Calc_Min_Distance(rp_type number, max_npp number, n1 number, n2 number) return number;  -- вычисляет расстояние между двумя треками npp по оптимальному направлению
  function Calc_Repair_robots(rpid_ number) return number;  -- сколько роботов на огурце находится в режиме починки?
  function calc_robot_nearest(rp_id in number, max_npp number, c_npp in number) return number; -- посчитать расстояние до ближайшего робота от указанного трека
  function calc_track_free_cell(rpid_ number, track_npp_ number) return number;  -- посчитать сколько в треке соводных ячеек для хранения
  function inc_spacing_of_robots(npp_ in number, direction in number, spr in number, rp_id_ in number,   -- возврашает номер участка пути увеличенное на spr секций
    minnppr in number default -1, maxnppr in number default -1 ) return number;
  function inc_npp(cur_npp in number, dir in number, rp_id_ number) return number; -- увеличивает указанный трек на 1 по направлению

  -- Get
  function Get_Another_Direction(direction_ in number) return number; -- получить иное направление движения
  function get_another_robot_id(r_id_ in number) return number; -- получить id второго робота
  function Get_Cell_ID_By_Name(rp_id_ in number, sname_ in varchar2) return number;  -- взять ID ячейки по ее имени на конкретном огурце
  function Get_Cell_Name_By_Track_ID(track_id_ in number) return varchar2;  -- получить имя ячейки по ID трека (для команды робота move)
  function Get_Cell_Name_By_Track_Npp(track_npp_ in number, rp_ number) return varchar2; -- получить имя ячейки по № секции на конкретном огурце (нужно для команды move)
  function Get_Cell_Shelving_ID(cell_id_ number) return number;  -- получить ID стеллажа по ID ячейки
  function Get_Cell_Track_Npp(cell_id_ number) return number;  -- взять номер трека по ID ячейки
  function get_container_cell_sname(container_barcode_ varchar2) return varchar2;  -- получить имя ячейки хранения контейнера по его ШК
  function Get_Cmd_Dir_Text(dir_ in number) return varchar2; -- получить по ID направления кусок команды в текстовом виде для отдачи роботу

  function get_cmd_max_priority(rp_id_ number) return number; -- получить максимальный приоритет активной команды по подскладу
  function Get_Cmd_RP_Min_NS_ID(rp_id_ number) return number;  -- получить минимальный ID активной команды в указанном огурце
  function Get_Cmd_RP_Min_NS_ID(rp_id_ number, pri_ number) return number;  -- получить минимальный ID активной команды в указанном огурце в указанном приоритете
  function Get_Cmd_RP_Order_After_Min(rpid_ number, cmdrpid_ number) return number;  -- получить порядковый № команды перемещения контейнеров в огурце после минимально активной
  function Get_Cmd_RP_Order_After_Min(rpid_ number, pri_ number, cmdrpid_ number) return number; -- получить порядковый № команды перемещения контейнеров в огурце после минимально активной в заданном приоритете
  function Get_Cmd_RP_Time_Work(crpid_ number) return number;  -- сколько уже времени в секундах исполняется команда?
  procedure get_next_npp(rp_type number, max_npp in number, cur_npp in number, npp_to in number, 
      dir in number, next_npp out number, is_loop_end out number);  -- взять следующий № трека по направлению (и высчитать, не пришди ли уже куда надо)
  function get_real_min_abc_zone(rpid number) return number; -- получить минимальную зону хранения товара для подсклада
  function Get_RP_CIA_State(rp_id_ number) return number; -- есть ли какие-то роботы в огурце с командами?
  function Get_RP_Command_State(rpid_ number) return number;  -- есть ли на подскладе какие-то назначенные на роботов команды перемещения контейнеров
  function Get_RP_Name(rpid_ number) return varchar2;  -- получить имя огурца
  function Get_RP_Num_Of_robots(rpid_ number) return number;  -- сколько в огурце роботов?
  function Get_RP_Robots_State(rp_id_ number) return number;  -- есть ли какие-то роботы в огурце активные (не готовы и не в починке)?
  function Get_RP_Spacing_Of_robots(rpid_ number) return number;  -- получить минимальное расстояние между роботами в огурце
  function get_track_id_by_cell_and_robot(sname_ in varchar2, robot_id_ in number) return number; -- получить ID трека по названию ячейка и ID робота
  function get_track_id_by_cell_and_rp(rp_id_ in number, sname_ in varchar2) return number; -- получить ID трека по огурцу и названию ячейки
  function Get_Track_ID_By_Npp(npp_ in number, rp_id_ in number) return number;  -- взять ID трека по его номеру на конкретном огурце
  function get_track_id_by_robot_and_npp(robot_id_ in number, track_no in number) return number; -- получить ID трека по ID роботу и № трека
  function get_track_npp_by_cell_and_rp(rp_id_ in number, sname_ in varchar2) return number; -- взять № трека по огурцу и названию ячейки
  function get_track_npp_by_npp(npp_ in number, rp_id_ in number) return number;  -- проверить, есть ли возвращенный номер трека в базе. Если нет, попытаться найти № трека по имени
  function get_track_npp_by_id(id_ in number) return number; -- взять № трека по его ID

  function Get_Track_Npp_Not_Baned(rp_id_ number, npp_ number, dir_ number) return number; -- получить ближайший трек по заданному направлению, в который можно делать move  
  function get_transit_1rp_cell(rpid_ number) return number;  -- получить id свободной транзитной ячейки для передач внутри одного огурца


  -- проверяет блокировку вокруг робота, и, если надо, блокирует
  function Check_Lock_Robot_Around(rid_ number, npp_ number) return number;  -- проверяем - заблокирован ли ореол вокруг робота?
  procedure Check_New_Robot_Npp_Correct(rid_ number, npp_ number); -- проверяем корректность нахождения робота в треке, если что не так, то raise
  procedure Check_WPR_Lock(rpid_ number); -- проверяем на корректность блокировки для команд роботов, которые находятся в ожидании решения проблемы


  function Try_Track_Lock(rid_ number, npp_to_ number, dir_ number , 
     IsIgnoreBufTrackOrder boolean, barrier_robot_id out number) return number; -- очень хитрая функция блокировки трека - подробности см. в исходниках ф-ии
  function Try_Track_Lock_Robot_Around(rid_ number, npp_ number) return number;  -- пытаемся заблокировать трек в указанном месте + ореол вокруг робота
  procedure Unlock_Track(robot_id_ in number, rp_id_ number, npp_from_ in number,
      npp_to_ in number,dir_ in number); -- вызывается из триггера при смене текущего трека; нужно передавать rp_id_, чтобы не было мутации
  procedure unlock_track_after_cmd_error(robot_id_ in number); -- разблокировать трек после ошибки команды робота

  function Robot_Stop_Drive_Away_Try(rid_ number, tor_id_ number) return number;  -- прогоняем робота мешающего к треку по направлению

  -- не публичные, но вынесены сюдя для проверки
  procedure Group_Op_To_Simple_CRP(rp_id_ number);  -- преобразование групповых операций перемещения в обычные
  procedure Change_Work_Status(rpid_ number);  -- меняет статус работа/пауза указанного огурца
  procedure Robot_Cmd_RP_Change_Dir(rid_ number);  -- сменить направление команды перемещения контейнера для конкретного робота


  procedure crash_test_linear_tact; -- линейный такт креш-теста 

  -- всякие действия
  procedure Actione_From_Pause(rp_id_ number); -- действия, необходимые при снятии подсклада с паузы
  procedure cancel_active_cmd(rp_id_ number); -- снимает с подсклада все активные команды, а находящиеся на них контейнеры помечает как вне склада
  procedure change_cmd_rp_goal(cmd_rp_id_ number, new_cell_dest_id number); -- назначаем новую целевую ячейки команде перемещения контейнера
  procedure Container_Change_Placement(BC_ varchar2,rp_id_ number,cell_id_ number);  -- назначить новое место реального расположения контейнера
  procedure try_assign_new_unload_cell(old_cell_id number, robot_id_ number, cellrec out cell%rowtype, dir out number);  -- пытаемся назначить новую ячейку выгрузки вместо старой


end obj_rpart;
/
