create or replace package service is  -- модуль сервисных функций. Некоторые из них устарели и перенесены в профильные объекты

  bkp_to_file_active number:=1;  -- писать в лог короткий бэкап?

  function get_2d_word_beg(s varchar2) return number;  -- взять первые два слова из строки
  function get_3d_word_beg(s varchar2) return number;  -- взять первые три слова из строки
  function get_another_gd(cnt_id number, gd_id_ varchar2, max_size number default 4000) return varchar2;  -- взять список иного товара, что лежит в контейнере
  function get_another_robot_id (rid number) return number; -- взять второй робот на огурце
  function get_cell_storage_state(is_full in number, is_error in number, is_realy_bad in number) return number;  -- получить статус ячейки хранения
  function get_cells_for_ustirovka(rp_id number,nppfrom number, nppto number) return varchar2;  -- получить ячейки для юстировки
  function get_cells_for_ustirovka_short(rp_id number,nppfrom number, nppto number) return varchar2;  -- получить ячейки для юстировки короткий
  function get_cnt_name_on_robot(rid_ number) return varchar2;  -- получить ШК контейнера, что сейчас на роботе
  function get_container_sum_qty(cnt_id_ number) return number;  -- сколько штук товара в контейнере?
  FUNCTION get_corr_shelving_id(shid in number) return number;  -- получить соотв. стеллаж на другом подскладе
  function get_free_rest(gd_id_ in varchar2, pfirm_id in number) return number;  -- получить свободный остаток 
  procedure get_last_cmd(comp_name_ varchar2,   -- получить информацию о состоянии последней команды, отданной с указанного компьютера
    cmd_name out varchar2,cmd_name_full out varchar2, dt_cr out varchar2, sost out varchar2, error_ out varchar2);
  function get_max_cmd_priority return number;  -- получить максимальный приоритет активной команды
  
  function get_robot_ci_cnt_bc(rid_ number) return varchar2;  -- взять № контейнера command_inner команды по id роботу
  function get_robot_ci_cell_src(rid_ number) return varchar2;  -- взять № ячейки источник command_inner команды по id роботу
  function get_robot_ci_cell_dst(rid_ number) return varchar2;  -- взять № ячейки назначения command_inner команды по id роботу
  function get_robot_name(rid_ number) return varchar2;  -- получить имя робота по ID
  function get_robot_stop_param(rid_ number) return number;  -- получить список доп. параметров для решения проблемы
  function get_rp_param_number(cpn varchar2, def number default 0) return number;  -- взять числовой параметр всего АСК
  function get_rp_param_string(cpn varchar2, def varchar2 default null) return varchar2;  -- взять строковый параметр всего АСК
  function get_sec(ss in number) return float;  -- перевод секунд в дни
  function get_ust_cell_dir(rid number, gtid in number) return number;  -- взять направление для юстировки

  function is_cell_accept_enable(cfull number,cfullmax number,cid number) return number;  -- возвращает 1, если можно еще дать команду в эту ячейку (проверяет is_full и блокировки)
  function is_cell_cmd_locked(cid number) return number;  -- заблокирована ли ячейка командой?
  function is_cell_full_check return number;  -- ячейка полностью проверена?
  function is_cell_near_edge(cid_ number) return number;  -- ячейка возде края №№ треков?
  function is_cell_on_comp(cid_ number, cname varchar2) return number;  -- ячейка закреплена за компьютером?
  function is_cell_over_locked(cid number) return number;  -- не перезаблокирование ли ячейки командами?
  function is_free_way(rid number,rnpp number,gnpp number, dir number,maxnpp number,rpid number) return boolean;  -- путь свободен?
  function is_hibernate return number;  -- может ли система заснуть?
  function is_way_free_for_robot(rid_ number, npp_from number, npp_to number) return number;  -- путь свободен для робота?

  procedure add_shelving_need_to_redraw(shelving_id_ number);  -- добавить стеллаж к списку для перерисования
  procedure bkp_to_file(fname in varchar2, ss varchar2);  -- строку в журнал

  function calc_ideal_crp_cost(rp_id_ number, csrc_id number, cdest_id number) return number;  -- посчитать идеальную цену команды перемещения контейнера
  procedure cancel_all_verify_cmd;  -- отменить все команды верификации
  function cell_acc_only_1_robot(src_ number, dst_ number) return number;  -- ячейка достижима лишь для одного робота? (для линейных огурцов)
  procedure cell_lock_by_cmd(cid number,cmd_id_ number); -- заблокировать ячейку командой
  procedure cell_unlock_from_cmd(cid number,cmd_id_ number);  -- разблокируем ячейку от команды
  procedure change_cc_qty(cnt_id_ number, gd_id_ varchar2, dqty number, gdp_id_ number);  -- изменяем кол-во товара в контейнере
  procedure clear_form_opened;  -- удаляем информацию по открытым формам 
  procedure clearlogfile;  -- перезаписать общий лог файл
  procedure clearlogfilen(fn in varchar2);  -- перезаписать указанный лог файл

  procedure log_moci;  -- устаревшая функция очень детального лога
  procedure log2file(txt in varchar2, pref varchar2 default 'log_');  -- записать строку в лог
  procedure log2filen(fn in varchar2,txt in varchar2);  -- записать строку в файл
  function recover_last_ocil return date; -- устаревшая функция восстановления из лога
  procedure robot_goto_cell(rid_ number, sname_ varchar2);  -- команда перемещения робота к ячейке
  procedure unlock_all_not_ness(rid in number);  -- разблокируем все, заблокированное текущим роботом кроме расстояния вокруг робота

  
  function empty_cell_capability(cfull number,cfullmax number,cid number) return number;  -- сколько еще может влезть коман в ячейку


  function ml_get_val(var_name_ varchar2, val_def_ varchar2) return varchar2;  -- мультиязычность - получить значение 
  function ml_get_rus_eng_val(in_rus varchar2, in_eng varchar2) return varchar2;  -- мультиязычность - получить значение в зависимости от языка
  procedure make_bkp_stamp; -- залоггировать состояние АСК
  procedure make_bkp_good;  -- залоггировать состояние с товарами  
  procedure mark_cell_as_free(cid in number, container_id_ in number , robot_id_ in number); --- пометить ячейку как свободную
  procedure mark_cell_as_full(cid in number, container_id_ in number, robot_id_ in number);  -- пометить ячейку как полную

  function op_last_cmd_repeat(comp_name_ varchar2) return number;  -- повторить последнюю команду оператора с компьютера
  function op_last_cmd_mark_as_ok(comp_name_ varchar2) return number; -- пометить последнюю команду оператора как исполненную ОК 


  procedure test;  -- тестирование 
  procedure test_raise_wrap;  -- тестирование исключения
  function to_number_my(ss in varchar2) return number;  -- преобразовать строку в число
  function to_number_from_left(ss varchar2) return number;  -- преобразовать строку в число слева



  function shelving_has_error_cell(shid in number) return number;  -- есть ли ошибочные ячейки в стеллаже?
  function set_robot_mode_to_repair(rid_ number, npp_rep number, param number) return varchar2;  -- устаревшая функция перевода робота в режим починки
  function set_robot_repair_done(rid_ number) return varchar2;  -- устаревшая функция вывода робота из починки
  procedure set_rp_param_number(cpn varchar2, param_ number);  -- установка числового параметра АСК 
   


  procedure who_called_me( owner      out varchar2,  -- полная информация из стека вызова
                         name       out varchar2,
                         lineno     out number,
                         caller_t   out varchar2 );

  function who_am_i return varchar2; -- краткая информация из стека вызова


end;
/
