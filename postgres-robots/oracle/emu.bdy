create or replace package body emu is -- пакет для эмулятора группы роботов АСК

-- инициализировать трек с ранее считанного
procedure init_ttrack_from_rp_var is
begin
  ttrack:=rp_ttrack;
end;

-- расшифровать направление эмулятора в обычное
function decode_dir(dir in number, no /*1 или 2*/ in number) return number is
begin
  if no=1 then
    if dir in (1,2) then
      return 1;
    else
      return 0;
    end if;
  else
    if dir in (1,3) then
      return 1;
    else
      return 0;
    end if;
  end if;
end;

-- запись в лог
procedure mo_log(s in varchar2) is
begin
  if emu_log_level<>0 then
  if log_trigger=1 then
    service.log2filen('molog',s);
  else
    dbms_output.put_line(to_char(systimestamp,'hh24:mi:ss.ff')||' '||s);
  end if;
  end if;
end;

-- взять номер другого робота
function get_another_robot_num(rnum in number) return number is
begin
  if rnum=1 then
     return 2;
  else
     return 1;
  end if;
end;

-- запись в лог
procedure emu_log(lstr in varchar2) is
  cnt number;
begin
  if emu_log_level<>0 then
    if log_trigger=0 then
      DBMS_OUTPUT.put_line (to_char(systimestamp,'hh24:mi:ss.ff')||'; '||lstr);
    else
      service.log2filen('emulog',lstr);
    end if;
  end if;
end;

-- запись в лог
procedure emu_log_new(ll in number,lstr in varchar2) is
begin
  if ll<=emu_log_level then
    if log_trigger=0 then
      DBMS_OUTPUT.put_line (to_char(systimestamp,'hh24:mi:ss.ff')||'; '||lstr);
    else
      service.log2filen('emulog',lstr);
    end if;
  end if;
end;

-- проверка корректности трека
procedure check_locking_consistence is
  -- 0 -не было еще, 1 - появился, 2 - пропал, 3 - появился после пропажи
 type trr is record (state number,  id number);
 type ttrr is table of trr index by binary_integer;
 rr ttrr;
 anrocnt number;
begin
  return;
  if check_ttrack_consistence=0 then
    return;
  end if;
  for j in 1..rp_rec.num_of_robots loop
    rr(j).state:=0;
    rr(j).id:=0;
  end loop;
  for i in 0..rp_rec.ttt_cnt loop
    if ttrack(i).locked_by_robot_id<>0 then
      if rr(1).id=0 then
        -- назначаем первого робота
        rr(1).id:=ttrack(i).locked_by_robot_id;
      elsif rr(2).id=0 and rr(1).id<>ttrack(i).locked_by_robot_id then
        -- назначаем второго робота
        rr(2).id:=ttrack(i).locked_by_robot_id;
      elsif rr(1).id<>ttrack(i).locked_by_robot_id and rr(2).id<>ttrack(i).locked_by_robot_id then
        raise_application_error (-20003, 'Ошибка проверки целостности блокировки - лишний robot_id='||ttrack(i).locked_by_robot_id||' при i='||i , TRUE);
      end if;
    end if;
    for j in 1..2 loop
      anrocnt:=get_another_robot_num(j);
      if ttrack(i).locked_by_robot_id<>0 then
        if ttrack(i).locked_by_robot_id=rr(j).id then
          -- блокировка текущим роботом
          if rr(j).state=0 then
             -- появился
             rr(j).state:=1;
          elsif rr(j).state=2 then
             -- появился после пропажи
             if ttrack(0).locked_by_robot_id=rr(j).id then
                rr(j).state:=3;
             else
                raise_application_error (-20003, 'MO1: Ошибка проверки целостности блокировки -  появился робот после пропажи не в конце пути npp='||i, TRUE);
             end if;
          end if;
          if rr(anrocnt).state = 1 then
             rr(anrocnt).state:= 2;
          elsif rr(anrocnt).state = 3 then
             raise_application_error (-20003, 'Ошибка проверки целостности блокировки -  исчез робот до конца пути npp='||i, TRUE);
          end if;
        end if;
      else -- нулевой бокировка - никем не забл
        if rr(j).state = 1 then
           rr(j).state:= 2;
        elsif rr(j).state = 3 then
           raise_application_error (-20003, 'Ошибка проверки целостности блокировки -  исчез робот до конца пути npp='||i, TRUE);
        end if;
      end if;
    end loop;
  end loop;
end;

-- получить следующий № трека
procedure get_next_npp(cur_npp in number, npp_to in number, dir in number, next_npp out number, is_loop_end out number) is
begin
  is_loop_end:=0;
  if cur_npp=npp_to then
    is_loop_end:=1;
  end if;
  if dir=1 then -- по часовой
    if cur_npp<rp_rec.ttt_cnt then
       next_npp:= cur_npp+1;
    elsif cur_npp=rp_rec.ttt_cnt then
       next_npp:=0;
    else
       if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
    end if;
  else
    if cur_npp>0 then
       next_npp:= cur_npp-1;
    elsif cur_npp=0 then
       next_npp:=rp_rec.ttt_cnt;
    else
       if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
    end if;
  end if;
end;

-- увеличить № трека по направлению
function inc_npp_prim(cur_npp in number, dir in number, max_npp in number) return number is
  next_npp number;
begin
  if dir=1 then -- по часовой
    if cur_npp<max_npp then
       next_npp:= cur_npp+1;
    elsif cur_npp=max_npp then
       next_npp:=0;
    end if;
  else
    if cur_npp>0 then
       next_npp:= cur_npp-1;
    elsif cur_npp=0 then
       next_npp:=max_npp;
    end if;
  end if;
  return next_npp;
end;

-- увеличить № трека на 1
function inc_npp(cur_npp in number, dir in number) return number is
  next_npp number;
begin
  if dir=1 then -- по часовой
    if cur_npp<rp_rec.ttt_cnt then
       next_npp:= cur_npp+1;
    elsif cur_npp=rp_rec.ttt_cnt then
       next_npp:=0;
    else
       if emu_log_level>=1 then emu_log('  inp: Error cur_npp='||cur_npp); end if;
    end if;
  else
    if cur_npp>0 then
       next_npp:= cur_npp-1;
    elsif cur_npp=0 then
       next_npp:=rp_rec.ttt_cnt;
    else
       if emu_log_level>=1 then emu_log('  inp: Error cur_npp='||cur_npp); end if;
    end if;
  end if;
  return next_npp;
end;

-- запись в лог трека
procedure log_tmp_track is
  rr varchar2(400);
begin
  if emu_log_level>=3 then
    rr:=' ';
    for tcnt in 0..rp_rec.ttt_cnt loop
      --emu_log('tcnt='||tcnt);
      rr:=rr||ttrack(tcnt).locked_by_robot_id;
    end loop;
    emu_log(rr);
  end if;
  if rp_rec.num_of_robots>1 then
    check_locking_consistence;
  end if;
end;

-- инициализация трека с базы
procedure init_ttrack(rp_id_ in number) is
begin
  if emu_log_level>=11 then
    emu_log('init_ttrack: - начало');
  end if;
  rp_rec.ttt_cnt:=0;
  rp_rec.id:=rp_id_;
  rp_rec.min_npp:=0;
  select id, repository_type, spacing_of_robots, num_of_robots
  into rp_rec.id, rp_rec.repository_type, rp_rec.sorb, rp_rec.num_of_robots
  from repository_part where id=rp_id_;
  for t in (select tr.id, tr.npp, cell_sname sname, tr.length, tr.speed, tr.locked_by_robot_id
            from track tr
            where repository_part_id=rp_id_
            order by npp) loop
    ttrack(rp_rec.ttt_cnt).id:=t.id;
    ttrack(rp_rec.ttt_cnt).npp:=t.npp;
    ttrack(rp_rec.ttt_cnt).length:=t.length;
    ttrack(rp_rec.ttt_cnt).speed:=t.speed;
    ttrack(rp_rec.ttt_cnt).cell_sname:=t.sname;
    ttrack(rp_rec.ttt_cnt).locked_by_robot_id:=nvl(t.locked_by_robot_id,0);
    rp_rec.max_npp:=t.npp;
    rp_rec.ttt_cnt:=rp_rec.ttt_cnt+1;
  end loop;
  rp_rec.ttt_cnt:=rp_rec.ttt_cnt-1;
  log_tmp_track;
  if emu_log_level>=11 then
    emu_log('init_ttrack: - завершение');
  end if;
end;

-- получить № трека по его ID
function get_ttrack_npp_by_id(tid in number) return number is
begin
  for i in 0..rp_rec.ttt_cnt loop
    if ttrack(i).id=tid then
      return(i);
    end if;
  end loop;
  if emu_log_level>=1 then emu_log('  gtnbi: ERROR - выход за рамки массива ttrack с id='||tid); end if;
  return -1;
end;


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
                      cpl_xml_ in varchar2,          -- промежуточные точки - <CPL>  <cp type="53" datetime="15.12.2020 14:34:27" /> </CPL>
                      current_track_id out number,-- положение робота на текущий момент
                      command_finished out number, -- завершена ли команда к текущему моменту: 0 - нет, 1 - да
                      use_cmd_emu_info in number default 0 -- использовать переменную инфо команды для ускорения
                      ) is
  cei_loc T_cmd_emu_info;
  tpos number;
  t_start_m number;
  t_stop_m number;
  track_rec_b_npp number;
  track_rec_e_npp number;
  dir number;
  sec_past number;
  current_track_npp number;
  xml XMLType;


  procedure ce_end_log is
  begin
    if emu_log_level>=2 then
      emu_log('  ce завершение: cur_track_npp='||current_track_npp||'; command_finished='||command_finished);
    end if;
  end;

  -- функция движения
  function move return number is
    is_loop_exit number;
    nctn number;
  begin
    current_track_npp:=track_rec_b_npp;
    if track_rec_e_npp=track_rec_b_npp then
      return 1; -- уже там где надо - нет нужды двигаться
    end if;
    if (date_time_begin+ (cei_loc.t_start_m/86400)) >= date_time_now then
      -- по времени еще не тронулись с места - разгонямся только
      return 0;
    end if;
    sec_past:=cei_loc.t_start_m; -- тронулись
    loop
      sec_past:=sec_past+ttrack(current_track_npp).length/ttrack(current_track_npp).speed;
      current_track_id:=ttrack(current_track_npp).id;
      if date_time_begin+ sec_past/86400 >= date_time_now
         and current_track_npp<>track_rec_e_npp then
        return 0;
      end if;
      get_next_npp(current_track_npp,track_rec_e_npp,dir,nctn,is_loop_exit);
      exit when is_loop_exit=1;
      current_track_npp:=nctn;
    end loop;
    if date_time_begin+ (sec_past+cei_loc.t_stop_m)/86400 >= date_time_now then
      return 0; -- дошли куда надо но еще не остановились
    else
      sec_past:=sec_past+cei_loc.t_stop_m;
      return 1;
    end if;
  end;
  -- взять инфо по точке останова  №
  procedure get_ecp_data(no_ number, cp out number, dt out date) is
    r number;
  begin
    r:=0;
    for ecp in (select * from emu_checkpoint where robot_id=r_id order by dt) loop
      r:=r+1;
      if no_=r then
        cp:=ecp.npp;
        dt:=ecp.dt;
        return;
      end if;
    end loop;
    cp:=null;
    dt:=null;
  end;
  -- функция движения с промежуточными точками -- ее менять!
  function move_cp return number is
    is_loop_exit number;
    nctn number;
    ecp_pos number;
    ecp_npp number;
    ecp_dt date;
    was_stop boolean;
  begin
    current_track_npp:=track_rec_b_npp;
    if track_rec_e_npp=track_rec_b_npp then
      return 1; -- уже там где надо - нет нужды двигаться
    end if;
    sec_past:=0;
    ecp_pos:=1; -- первая точка останова
    was_stop:=true;
    loop
      get_ecp_data(ecp_pos, ecp_npp,ecp_dt);
      dbms_output.put_line('get_ecp_data ecp_pos='||ecp_pos||' ecp_npp='||ecp_npp||' ecp_dt='||to_char(ecp_dt,'dd.mm.yy hh24:mi:ss'));
      if ecp_npp is null then -- вышли за пределы точек останова, но конечная еще не достигнута
         dbms_output.put_line('за пределами');
         if current_track_npp=track_rec_e_npp then
           dbms_output.put_line('1');
           return 1;
         else
           dbms_output.put_line('0');
           return 0;
         end if;
      end if;
      if date_time_begin+ sec_past/86400 >=ecp_dt then
        if was_stop then
           was_stop:=false;
           sec_past:=sec_past+cei_loc.t_start_m;
           if date_time_begin+ sec_past/86400 >= date_time_now
              and current_track_npp<>track_rec_e_npp then
             return 0;
           end if;
        end if;
        sec_past:=sec_past+ttrack(current_track_npp).length/ttrack(current_track_npp).speed;
        dbms_output.put_line('  current_track_npp='||current_track_npp||' sec_paste='||to_char(date_time_begin+ sec_past/86400,'dd.mm.yy hh24:mi:ss'));
        current_track_id:=ttrack(current_track_npp).id;
        if date_time_begin+ sec_past/86400 >= date_time_now
           and current_track_npp<>track_rec_e_npp then
          return 0;
        end if;
        if current_track_npp=ecp_npp then
           ecp_pos:=ecp_pos+1;
        else
          get_next_npp(current_track_npp,track_rec_e_npp,dir,nctn,is_loop_exit);
          exit when is_loop_exit=1;
          current_track_npp:=nctn;
        end if;
      else
        was_stop:=true;
        sec_past:=sec_past+1;
        dbms_output.put_line('  current_track_npp='||current_track_npp||' sec_paste='||to_char(date_time_begin+ sec_past/86400,'dd.mm.yy hh24:mi:ss'));
      end if;
    end loop;

    if date_time_begin+ (sec_past+cei_loc.t_stop_m)/86400 >= date_time_now then
      return 0; -- дошли куда надо но еще не остановились
    else
      sec_past:=sec_past+cei_loc.t_stop_m;
      return 1;
    end if;
  end;
begin
  mo_log('command_emu: robot_id='||robot_id||'; '||
           'date_time_begin='||to_char(date_time_begin,'dd.mm.yyyy hh24:mi:ss')||'; '||
           'date_time_now='||to_char(date_time_now,'dd.mm.yyyy hh24:mi:ss')||'; '||
           'begin_track_id='||begin_track_id||'; '||
           'command_type='||command_type||'; '||
           'cell_src='||cell_src||'; '||
           'cell_dst='||cell_dst||'; '||
           'direction='||direction||'; im_npp_='||im_npp_||'; cpl_xml_='||cpl_xml_);

  delete from emu_checkpoint where robot_id=r_id;
  if nvl(im_npp_,-1)>=0 then
    insert into emu_checkpoint(npp,dt,r_id) values(im_npp_,date_time_begin,robot_id);
  end if;

  xml := XMLType(cpl_xml_);
  for cc in (select
                 extractValue	(l.Column_VALUE, './/@npp') npp_,
                 extractValue	(l.Column_VALUE, './/@datetime') datetime_
               from table(XMLSequence(extract(xml, './/CPL/cp'))) l
               ) loop
      dbms_output.put_line(cc.npp_||' '|| cc.datetime_);
      insert into emu_checkpoint(npp,dt,r_id) values(to_number(cc.npp_),to_date(cc.datetime_,'dd.mm.yyyy hh24:mi:ss'),robot_id);
  end loop;


  command_finished:=0;
  sec_past:=0;
  if use_cmd_emu_info=1 then
    cei_loc:=cmd_emu_info;
  else
    cei_loc.begin_track_id:=begin_track_id;
    select npp into cei_loc.begin_track_npp
    from track where id=begin_track_id;
    select repository_part_id, time_load+time_unload, time_targeting, time_start_move, time_stop_move
    into rp_rec.id,  cei_loc.tl_pl_tul , cei_loc.tpos , cei_loc.t_start_m, cei_loc.t_stop_m
    from robot where id=robot_id;
    select repository_type, max_npp
    into rp_rec.repository_type, rp_rec.max_npp
    from repository_part where id=rp_rec.id;
    init_ttrack(rp_rec.id);
    if cell_dst is not null then
       select npp into cei_loc.dst_track_npp
       from track
       where repository_part_id=rp_rec.id
             and id in (select track_id from shelving where
                        id in (select shelving_id from cell where sname=cell_dst));
    end if;
    if cell_src is not null then
       select npp into cei_loc.src_track_npp
       from track
       where repository_part_id=rp_rec.id
             and id in (select track_id from shelving where
                        id in (select shelving_id from cell where sname=cell_src));
    end if;
  end if;
  current_track_id:=cei_loc.begin_track_id;
  current_track_npp:=cei_loc.begin_track_npp;
  /*if emu_log_level>=2 then
    emu_log('command_emu: robot_id='||robot_id||'; '||
           'date_time_begin='||to_char(date_time_begin,'hh24:mi:ss')||'; '||
           'date_time_now='||to_char(date_time_now,'hh24:mi:ss')||'; '||
           'begin_track_npp='||cei_loc.begin_track_npp||'; '||
           'command_type='||command_type||'; '||
           'cell_src='||cell_src||'; '||
           'cell_dst='||cell_dst||'; '||
           'direction='||direction);
  end if;  */

  --***********************************************************
  --move
  --***********************************************************
  if command_type=1 then
    dir:=direction;
    track_rec_b_npp:=cei_loc.begin_track_npp;
    track_rec_e_npp:=cei_loc.dst_track_npp;
    if cei_loc.dst_track_npp is null then
      raise_application_error (-20013, 'Ошибка - в COMMAND_EMU вызывана команда MOVE с NULL ключевым параметром', TRUE);
    end if;
    if move=1 then -- переместить успели
      -- раз сюда дошли, то команда MOVE закончилась
      command_finished:=1;
    end if;
  --***********************************************************
  --inity
  --***********************************************************
  elsif command_type=32 then
      if (date_time_begin+ 12/86400)<= date_time_now then
        command_finished:=1;
      end if;
  --***********************************************************
  --unload
  --***********************************************************
  elsif command_type=3 then
    dir:=direction;
    track_rec_b_npp:=cei_loc.begin_track_npp;
    track_rec_e_npp:=cei_loc.dst_track_npp;
    if cei_loc.dst_track_npp is null then
      raise_application_error (-20013, 'Ошибка - в COMMAND_EMU вызывана команда UNLOAD с NULL ключевым параметром', TRUE);
    end if;
    if nvl(im_npp_,-1)>=0 then -- с промежуточной точкой
      --track_rec_e_npp:=im_npp_;
      if move_cp=1 then -- передвижение завершено
        dbms_output.put_line('move_cp=1');
        -- успеем выгрузить?
        if track_rec_b_npp= track_rec_e_npp then
          tpos:=0;
        else
          tpos:=cei_loc.tpos;
        end if;
        sec_past:=sec_past+cei_loc.tl_pl_tul+tpos;
        if (date_time_begin+ sec_past/86400)<= date_time_now then
          command_finished:=1;
        end if;
      end if;
    else -- обычная команда
      if move=1 then -- передвижение завершено
        -- успеем выгрузить?
        if track_rec_b_npp= track_rec_e_npp then
          tpos:=0;
        else
          tpos:=cei_loc.tpos;
        end if;
        sec_past:=sec_past+cei_loc.tl_pl_tul+tpos;
        if (date_time_begin+ sec_past/86400)<= date_time_now then
          command_finished:=1;
        end if;
      end if;
    end if;
  --***********************************************************
  --load
  --***********************************************************
  elsif command_type=4 then
    dir:=direction;
    track_rec_b_npp:=cei_loc.begin_track_npp;
    track_rec_e_npp:=cei_loc.src_track_npp;
    if cei_loc.src_track_npp is null then
      raise_application_error (-20013, 'Ошибка - в COMMAND_EMU вызывана команда LOAD с NULL ключевым параметром', TRUE);
    end if;
    if nvl(im_npp_,-1)>=0 then -- с промежуточной точкой
      --track_rec_e_npp:=im_npp_;
      if move_cp=1 then -- передвижение завершено
        dbms_output.put_line('move_cp=1');
        -- успеем выгрузить?
        if track_rec_b_npp= track_rec_e_npp then
          tpos:=0;
        else
          tpos:=cei_loc.tpos;
        end if;
        sec_past:=sec_past+cei_loc.tl_pl_tul+tpos;
        if (date_time_begin+ sec_past/86400)<= date_time_now then
          command_finished:=1;
        end if;
      end if;
    else -- обычная команда
      if move=1 then -- передвижение завершено
        -- успеем выгрузить?
        if track_rec_b_npp= track_rec_e_npp then
          tpos:=0;
        else
          tpos:=cei_loc.tpos;
        end if;
        sec_past:=sec_past+cei_loc.tl_pl_tul+tpos;
        if (date_time_begin+ sec_past/86400)<= date_time_now then
          command_finished:=1;
        end if;
      end if;
    end if;
  --***********************************************************
  --transfer
  --***********************************************************
  elsif command_type=2 then
    if rp_rec.REPOSITORY_TYPE=0 then -- только для линейного склада
      track_rec_b_npp:=cei_loc.begin_track_npp;
      track_rec_e_npp:=cei_loc.src_track_npp;
      if cei_loc.dst_track_npp is null or cei_loc.src_track_npp is null then
        raise_application_error (-20013, 'Ошибка - в COMMAND_EMU вызывана команда TRANSFER с NULL ключевым параметром', TRUE);
      end if;
      if track_rec_e_npp>track_rec_b_npp then
        dir:=1;
      else
        dir:=0;
      end if;
      if move=1 then -- доехали таки
        -- успеем загрузить?
        sec_past:=sec_past+cei_loc.tl_pl_tul;
        if (date_time_begin+ sec_past/86400)<= date_time_now then
          track_rec_b_npp:=get_ttrack_npp_by_id(current_track_id);
          track_rec_e_npp:=cei_loc.dst_track_npp;
          if track_rec_e_npp>track_rec_b_npp then
            dir:=1;
          else
            dir:=0;
          end if;
          if move=1 then -- приехали таки
            sec_past:=sec_past+cei_loc.tl_pl_tul;
            if (date_time_begin+ sec_past/86400 )<= date_time_now then
              command_finished:=1;
            end if;
          end if;
        end if;
      end if;
    else -- если для кольцевого - пишем ошибку
      raise_application_error (-20002, 'Couldn''t  send TRANSFER command for circular repository part!', TRUE);
    end if;
  end if;
  ce_end_log;
end;

-- установить режим WMS блокировки робота
procedure set_robot_wms_state(rid_ number, st_ number) is
begin
  update robot set emu_wms_lock_state =st_ where id=rid_;
  commit;
end;

-- взять ID новой команды блокировки WMS
function get_wms_lock_cmd_id(ct_ number) return number is
  res number;
begin
   SELECT SEQ_WMS_L.nextval INTO res FROM dual;
   insert into WMS_ROBOT_LOCK_CMD (id,ct)
   values(res, ct_);
   commit;
   return res;
end;

-- начать реальную команду
procedure real_cmd_begin(rid_ number) is
begin
  update emu_robot_problem set state=5 where robot_id=rid_ and tttype_id=7 and state in (1,3);
  commit;
end;

-- сбролсить все эмуляции проблем
procedure reset_all_ep is
begin
  update emu_robot_problem set state=0 where state in (1,3);
  commit;

end;

-- сгенерировать новое состояние платформы при решении проблемы при работе эмулятора
procedure gen_new_platform_busy(rid_ number) is
begin
  for rr in (select * from robot where id=rid_) loop
    --if rr.platform_busy=1 then
      insert into emu_robot_problem (state, robot_id, type_id, tttype_id, set_platform_busy )
      values(1,rid_,6,8,0);
      commit;
    --else
    --end if;
  end loop;
end;

-- взять новое состояние платформы при решении проблемы при работе эмулятора
function get_new_platform_busy(rid_ number, pb_ number) return number is
begin
  for re in (select * from emu_robot_problem where state=1 and robot_id=rid_ and type_id=6 and tttype_id=8) loop
    update emu_robot_problem set state=5 where id=re.id;
    commit;
    if pb_=1 then
      return 0;
    else
      return 1;
    end if;
  end loop;
  return pb_;
end;

end emu;
/
