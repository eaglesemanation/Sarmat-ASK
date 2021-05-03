create or replace package emu is -- пакет для эмулятора группы роботов АСК

   -- типы данных для эмулятора
   type ttt_rec is record (id number, npp number, locked_by_robot_id number, speed number, length  number, cell_sname varchar2(100)); -- элемент трека
   TYPE ttt_table IS TABLE OF ttt_rec INDEX BY BINARY_INTEGER; -- таблица треков
   TYPE CPL_table IS TABLE OF emu_checkpoint%ROWTYPE INDEX BY PLS_INTEGER;
   type trp_rec is record (id number, repository_type number, min_npp number, max_npp number, ttt_cnt number, sorb number, num_of_robots number); -- огурец
   type tr_rec is record (mo_cmd_depth number, mo_emu_step number); -- общие параметры эмуляции

   type T_cmd_emu_info is record ( -- для эмуляции команды
       begin_track_id number,  -- начальное ID трека
       begin_track_npp number, -- начальный № трека
       src_track_id number,  -- ID трека-источника
       src_track_npp number, -- № трека-источника
       dst_track_id number,  -- ID трека-применика
       dst_track_npp number, -- № трека-применика
       tl_pl_tul number,  -- время выдвижения + время задвижения рабочего стола
       tpos number, -- время позиционирования робота
       t_start_m number,  -- время начала движения робота
       t_stop_m number  -- время полной остановки робота
   );
   cmd_emu_info T_cmd_emu_info; -- для command_emu
   ttrack ttt_table; -- track в ОЗУ
   rp_ttrack ttt_table; -- track в ОЗУ на подсклад зачитанный
   rp_rec trp_rec; -- подсклад в ОЗУ
   r_rec tr_rec; -- общая инфа в ОЗУ

   -- переменные для убирания вызовов sql в calc_transfer_cost
   wrk_crp_rec command_rp%rowtype; -- команда перемещения
   wrk_ci_rec command_inner%rowtype;  -- команда простая робота
   wrk_zay_rec track_order%rowtype;  -- заявка на трек

   /*type temu_rocom is record --
   (
       -- вначале инициализацмионные параметры
       id number,
       -- зачитываем из команды что анализируется
       dir1 number,
       dir2 number,
       tl_pl_tul number,
       command_rp_id number,
       cell_dest_sname varchar2(30),
       track_dest_id number,
       track_dest_npp number,
       cell_src_sname varchar2(30),
       track_src_id number,
       track_src_npp number,
       -- текущие данные - положене
       cur_track_id number,
       cur_track_npp number,
       cur_cell_sname varchar2(30),
       robot_state number ,
       -- текущее состояние команды
       cmd_state number,     -- 0- не начала вып. 1 - поехали, 2 - доехали до откуда надо,
                             -- 3 - взяли что надо, 4 - доехали до куда надо, 5 - выгрузили куда надо';
       cmd_inner_type number, -- тип команды что сейчас собирается делатьсмя
                              -- : 1 - move (dest), 2-  transfer,
                              -- 3 - unload(dest), 4 - load (src)
       -- параметры команды
       cmd_cell_src_sname varchar2(30),
       cmd_cell_dest_sname varchar2(30),
       cmd_dir number,
       cmd_track_src_id number,
       cmd_track_dest_id number,
       cmd_track_src_npp number,
       cmd_track_dest_npp number,
       -- начальное состояние команды
       cmd_time_begin number,
       cmd_cell_sname_begin varchar2(30),
       cmd_track_id_begin number,
       cmd_track_npp_begin number,
       -- по заявкам
       zay_is_fill number, -- есть ли заявка от данного робота?
       zay_id number,
       zay_npp_from number,
       zay_npp_to number,
       zay_dir number
   );
   type ttemu_rocom is table of temu_rocom
   index by binary_integer;
   r ttemu_rocom;*/

   log_trigger integer :=1; -- =0 - в таблицу log, =1 - в файл LOG =3 - dbms
   emu_log_level INTEGER := 1; -- 0- нет логов, 1 - минимум, 2 - средне, 3 - максимум
   check_ttrack_consistence integer :=1; -- проверять ли корректность трека на каждом шаге?
   --ssdate date :=to_date('01.01.2011 00:00:00','dd.mm.yyyy hh24:mi:ss');

procedure mo_log(s in varchar2); -- запись в лог


procedure init_ttrack(rp_id_ in number); -- взять данные по треку из текущих по огурцу

-- основная процедура - эмулятор команды
procedure command_emu(robot_id in number,         -- на робота
                      date_time_begin in date,    -- время начала выполнения команды
                      date_time_now in date,      -- время текушее
                      begin_track_id in number,   -- участок пути, на котором робот начал выполнение команды
                      command_type in number,     -- тип команды: 1 - move, 2-  transfer, 3 - unload, 4 - load
                      cell_src in varchar2,       -- название  ячейки-источника
                      cell_dst in varchar2,       -- название ячейки-приемника
                      direction in number,        -- направление: 1 - по часовой стрелки, -1 - против
                      im_npp_ in number,          -- промежуточная точка, =-1 или Null, если нет
                      cpl_xml_ in varchar2,          -- промежуточные точки
                      current_track_id out number,-- положение робота на текущий момент
                      command_finished out number, -- завершена ли команда к текущему моменту: 0 - нет, 1 - да
                      use_cmd_emu_info in number default 0 -- использовать переменную инфо команды для ускорения
                      );


function get_another_robot_num(rnum in number) return number;   -- взять номер другого робота
function get_new_platform_busy(rid_ number, pb_ number) return number;  -- сгенерировать новое состояние платформы при решении проблемы при работе эмулятора
procedure gen_new_platform_busy(rid_ number); -- взять новое состояние платформы при решении проблемы при работе эмулятора
function get_wms_lock_cmd_id(ct_ number) return number;  -- взять ID новой команды блокировки WMS

function decode_dir(dir in number, no /*1 ХКХ 2*/ in number) return number;  -- расшифровать направление эмулятора в обычное
function inc_npp_prim(cur_npp in number, dir in number, max_npp in number) return number;  -- увеличить № трека по направлению

procedure real_cmd_begin(rid_ number);  -- начать реальную команду
procedure reset_all_ep;  -- сбролсить все эмуляции проблем

procedure set_robot_wms_state(rid_ number, st_ number);  -- установить режим WMS блокировки робота



end emu;
/
