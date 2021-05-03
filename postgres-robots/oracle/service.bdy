create or replace package body service is

-- краткая информация из стека вызова
function who_am_i return varchar2 is
    l_owner        varchar2(30);
    l_name      varchar2(30);
    l_lineno    number;
    l_type      varchar2(30);
begin
   who_called_me( l_owner, l_name, l_lineno, l_type );
   return l_owner || '.' || l_name;
end;

-- взять первые два слова из строки
function get_2d_word_beg(s varchar2) return number is
  i number;
  w1_passed boolean;
  ss varchar2(4000);
begin
  ss:=s;
  i:=1; w1_passed :=false;
  loop
    if substr(ss, i, 1)=' ' then
      if not w1_passed then
        w1_passed:=true;
      end if;
    else
      if w1_passed then
        return i;
      end if;
    end if;
    i:=i+1;
    exit when i=length(ss);
  end loop;
  return -1;
end;

-- взять первые три слова из строки
function get_3d_word_beg(s varchar2) return number is
  ss varchar2(4000);
  sp1 number;
begin
  sp1:=get_2d_word_beg(s);
  ss:=substr(s, sp1);
  return get_2d_word_beg(ss)+sp1-1;
end;


-- информация из стека вызова
procedure who_called_me( owner      out varchar2,
                         name       out varchar2,
                         lineno     out number,
                         caller_t   out varchar2 )
as
    call_stack  varchar2(4096) default dbms_utility.format_call_stack;
    n           number;
    found_stack BOOLEAN default FALSE;
    line        varchar2(255);
    cnt         number := 0;
    pos1 number;
    pos2 number;
begin
--
    loop
        n := instr( call_stack, chr(10) );
        exit when ( cnt = 3 or n is NULL or n = 0 );
--
        line := substr( call_stack, 1, n-1 );
        --log2file('line='||line);
        call_stack := substr( call_stack, n+1 );
        --log2file('call_stack='||call_stack);
--
        if ( NOT found_stack ) then
            if ( line like '%handle%number%name%' ) then
                found_stack := TRUE;
            end if;
        else
            cnt := cnt + 1;
            -- cnt = 1 is ME
            -- cnt = 2 is MY Caller
            -- cnt = 3 is Their Caller
            if ( cnt = 3 ) then
                pos1:=get_2d_word_beg(line);
                pos2:=get_3d_word_beg(line);
                lineno := to_number(substr( line, pos1, pos2-pos1 ));
                line   := substr( line, pos2 );
                if ( line like 'pr%' ) then
                     n := length( 'procedure ' );
                 elsif ( line like 'fun%' ) then
                     n := length( 'function ' );
                 elsif ( line like 'package body%' ) then
                     n := length( 'package body ' );
                 elsif ( line like 'pack%' ) then
                     n := length( 'package ' );
                 elsif ( line like 'anonymous%' ) then
                     n := length( 'anonymous block ' );
                 else
                    n := null;
                end if;
                if ( n is not null ) then
                   caller_t := ltrim(rtrim(upper(substr( line, 1, n-1 ))));
                else
                   caller_t := 'TRIGGER';
                end if;

                line := substr( line, nvl(n,1) );
                n := instr( line, '.' );
                owner := ltrim(rtrim(substr( line, 1, n-1 )));
                name  := ltrim(rtrim(substr( line, n+1 )));
            end if;
        end if;
    end loop;
end;


-- получить свободный остаток 
function get_free_rest(gd_id_ in varchar2, pfirm_id in number) return number is
  res number;
begin
  if nvl(pfirm_id, 0) = 0 then
    select nvl(quantity, 0) into res
      from good_desc
     where id = gd_id_;
  else
    select nvl(sum(quantity) ,0) into res
      from firm_gd
     where gd_id = gd_id_
       and firm_id = pfirm_id;
  end if;
  return res;
end;

-- тестирование 
procedure test is
  s1 varchar2(4000);
    s2 varchar2(4000);
      s3 varchar2(4000);
        s4 varchar2(4000);
begin
  --OWA_UTIL.WHO_CALLED_ME
  who_called_me(s1,s2,s3,s4);
  --log2file(s1||'-'||s2||'-'||s3||'-'||s4);
end test;

-- взять второй робот на огурце
function get_another_robot_id (rid number) return number is
  res number;
begin
  --test;
  select id into res
  from robot
  where repository_part_id=(select repository_part_id from robot where id=rid)
        and id<>rid;
  return res;
end;

-- записать строку в файл
procedure log2filen(fn in varchar2,txt in varchar2) is
 file_handle  utl_file.file_type;
begin
 file_handle := sys.utl_file.fopen('LOG_DIR', fn, 'A');
 utl_file.put_line(file_handle, to_char(systimestamp,'hh24:mi:ss.ff')||' '||txt);
 utl_file.fclose(file_handle);
end log2filen;

-- записать строку в лог
procedure log2file(txt in varchar2, pref varchar2 default 'log_') is
 file_handle  utl_file.file_type;
 file_handle1  utl_file.file_type;
 fname varchar2(2500);
 sc varchar2(500);
 ss varchar2(4000); 
 s1 varchar2(500);
 s2 varchar2(500);
 s3 varchar2(500);
 s4 varchar2(500);
 res varchar2(500);
 pref_ varchar2(100);
begin
 pref_:=pref;
 who_called_me(s1,s2,s3,s4);
 res:= s1||' '||s2||' '||s3||' '||s4;
 if s2 in ('GAS','SORDER') and pref_='log_' then
   pref_:='fcm_';
 end if;

 file_handle := sys.utl_file.fopen('LOG_DIR', pref_||to_char(sysdate,'ddmmyy'), 'A');
 ss:=to_char(systimestamp,'hh24:mi:ss.ff')||' '||res||' '||txt; 
 loop  
   if length(ss)>250 then
     sc:=substr(ss,1,250);
     ss:=substr(ss,251);
   else
     sc:=ss;
     ss:='';
   end if;
   utl_file.put_line(file_handle, sc);
   exit when ss is null;
 end loop; 
 utl_file.fclose(file_handle);

 exception when others then
   fname:=pref_||to_char(sysdate,'ddmmyy')||DBMS_RANDOM.value(1,999);
   file_handle1 := sys.utl_file.fopen('LOG_DIR', fname, 'A');
   utl_file.put_line(file_handle1, to_char(systimestamp,'hh24:mi:ss.ff')||' '||txt);
   utl_file.fclose(file_handle1);

end log2file;


-- перезаписать общий лог файл
procedure clearlogfile is
 file_handle  utl_file.file_type;
begin
 file_handle := sys.utl_file.fopen('LOG_DIR', 'log', 'W');
 utl_file.put_line(file_handle, ' ');
 utl_file.fclose(file_handle);
end;

-- перезаписать указанный лог файл
procedure clearlogfilen(fn in varchar2) is
 file_handle  utl_file.file_type;
begin
 file_handle := sys.utl_file.fopen('LOG_DIR', fn, 'W');
 utl_file.put_line(file_handle, ' ');
 utl_file.fclose(file_handle);
end;

-- устаревшая функция очень детального лога
procedure log_moci is
  ocid number;
  cnt number;
  logs varchar2(250);
  mpr number;
  mcdepth  number;
  cmdtorun number;
  robot_free number;
begin
  return; -- пока нафиг
  select count(*) into cnt from ocil;
  if cnt>40 then
    -- удаляем старые, чтоб не мешались
    select max(id) into cnt from ocil;
    delete from ocil where id<cnt-40;
    commit;
  end if;
  insert into ocil (notes)
  values('') returning id into ocid;

  -- теперь пытаемся понять, какие команды мы анализировать будем
  select mo_cmd_depth into mcdepth from repository;
  for rpana in (select distinct rp.id, repository_type, spacing_of_robots
                  from sarmat.repository_part rp, sarmat.robot r
                 where r.repository_part_id=rp.id
                   and r.state=0 and is_present=1
                   and nvl(r.command_rp_id,0)=0
                   and repository_type<>0
                   and not exists (select * from track_order tor where rp.id=tor.repository_part_id)
                   and exists (select * from command_rp
                                where rp_id= rp.id
                                  and state=1
                                  and nvl(robot_id,0)=0)) loop
    select max(priority) into mpr from command_rp where rp_id=rpana.id and state=1 and command_type_id=3 and nvl(robot_id,0)=0;
    select count(*) into cmdtorun from sarmat.command_rp where rp_id=rpana.id and state=1 and command_type_id=3 and nvl(robot_id,0)=0;
    select count(*) into robot_free from sarmat.robot where repository_part_id=rpana.id and state=0 and nvl(command_rp_id,0)=0 and is_present=1;
    log2file('MO для подсклада '||rpana.id||' max_priority='||mpr||'; cmdtorun='||cmdtorun||'; robot_free='||robot_free);
    cnt:=0; logs:='  cmd_id=';
    for cmdana in (select id from sarmat.command_rp
                   where rp_id= rpana.id
                         and state=1
                         and priority=mpr
                         and command_type_id=3
                         and nvl(robot_id,0)=0 order by id) loop

      cnt:=cnt+1;
      if cmdtorun = 1 or robot_free = 1 then
        if cnt>mcdepth then
           exit;
        end if;
      else
        if cnt>mcdepth+1 then
           exit;
        end if;
      end if;
      logs:=logs||cmdana.id||' ';
    end loop;
    log2file(logs);
  end loop;

  insert into ocil_command (ocil_id, id, command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_rp_executed, container_rp_id, cell_src_id, cell_dest_id, npp_src, npp_dest, track_src_id, track_dest_id, crp_cell)
  select ocid,  id, command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_rp_executed, container_rp_id, cell_src_id, cell_dest_id, npp_src, npp_dest, track_src_id, track_dest_id, crp_cell
  from command where state in (1,3);

  insert into ocil_command_inner (ocil_id, id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, state, error_code_id, date_time_begin, date_time_end, command_rp_id, date_time_create, robot_id, command_to_run, track_src_id, track_dest_id, direction, cell_src_id, cell_dest_id, npp_src, npp_dest, track_id_begin, track_npp_begin, cell_sname_begin)
  select ocid,   id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, state, error_code_id, date_time_begin, date_time_end, command_rp_id, date_time_create, robot_id, command_to_run, track_src_id, track_dest_id, direction, cell_src_id, cell_dest_id, npp_src, npp_dest, track_id_begin, track_npp_begin, cell_sname_begin
  from command_inner where state in (1,3);

  insert into ocil_command_rp (ocil_id, id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_id, command_inner_executed, robot_id, direction_1, direction_2, substate, track_src_id, track_dest_id, sql_text_for_group, cell_src_id, cell_dest_id, npp_src, npp_dest, calc_cost, priority_inner, command_inner_last_robot_id, time_create)
  select ocid, id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_id, command_inner_executed, robot_id, direction_1, direction_2, substate, track_src_id, track_dest_id, sql_text_for_group, cell_src_id, cell_dest_id, npp_src, npp_dest, calc_cost, priority_inner, command_inner_last_robot_id, time_create
  from command_rp where state in (1,3);

  /*insert into ocil_robot (ocil_id, id, name, repository_part_id, ip, port, time_load, time_unload, color_fill, color_line, default_track_id, arrow_color, arrow_line_thikness, acceleration, braking_distance, braking, port_emu, current_track_id, state, cmd_error_descr, error_info_run_count, error_command_run_count, command_inner_id, letter, current_track_npp, command_rp_id, command_inner_assigned_id)
  select ocid, id, name, repository_part_id, ip, port, time_load, time_unload, color_fill, color_line, default_track_id, arrow_color, arrow_line_thikness, acceleration, braking_distance, braking, port_emu, current_track_id, state, cmd_error_descr, error_info_run_count, error_command_run_count, command_inner_id, letter, current_track_npp, command_rp_id, command_inner_assigned_id
  from robot;*/

  insert into ocil_track (ocil_id, id, repository_part_id, npp, length, name, angle, type, speed_mode_id, locked_by_robot_id, speed, cell_sname)
  select ocid, id, repository_part_id, npp, length, name, angle, type, speed_mode_id, locked_by_robot_id, speed, cell_sname
  from track;

  insert into ocil_track_order (ocil_id, id, date_time_create, robot_id, repository_part_id, npp_from, npp_to, direction)
  select ocid, id, date_time_create, robot_id, repository_part_id, npp_from, npp_to, direction
  from track_order;

  commit;
end;

function recover_last_ocil return date is
  oid number;
  rd date;
begin
  select nvl(max(id),0) into oid from ocil;
  if oid<>0 then
    select date_time into rd from ocil where id=oid;
    execute immediate 'truncate table command';
    execute immediate 'truncate table command_rp';
    execute immediate 'truncate table command_inner';
    execute immediate 'truncate table robot';
    execute immediate 'truncate table track_order';

    insert into command(id, command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_rp_executed, container_rp_id, cell_src_id, cell_dest_id, npp_src, npp_dest, track_src_id, track_dest_id, crp_cell)
    select id, command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_rp_executed, container_rp_id, cell_src_id, cell_dest_id, npp_src, npp_dest, track_src_id, track_dest_id, crp_cell
    from ocil_command
    where id=oid;

    insert into command_inner (id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, state, error_code_id, date_time_begin, date_time_end, command_rp_id, date_time_create, robot_id, command_to_run, track_src_id, track_dest_id, direction, cell_src_id, cell_dest_id, npp_src, npp_dest, track_id_begin, track_npp_begin, cell_sname_begin)
    select id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, state, error_code_id, date_time_begin, date_time_end, command_rp_id, date_time_create, robot_id, command_to_run, track_src_id, track_dest_id, direction, cell_src_id, cell_dest_id, npp_src, npp_dest, track_id_begin, track_npp_begin, cell_sname_begin
    from ocil_command_inner where ocil_id=oid;

    insert into command_rp (id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_id, command_inner_executed, robot_id, direction_1, direction_2, substate, track_src_id, track_dest_id, sql_text_for_group, cell_src_id, cell_dest_id, npp_src, npp_dest, calc_cost, priority_inner, command_inner_last_robot_id, time_create, container_id)
    select id, command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, error_code_id, date_time_begin, date_time_end, date_time_create, command_id, command_inner_executed, robot_id, direction_1, direction_2, substate, track_src_id, track_dest_id, sql_text_for_group, cell_src_id, cell_dest_id, npp_src, npp_dest, calc_cost, priority_inner, command_inner_last_robot_id, time_create, container_id
    from ocil_command_rp where ocil_id=oid;

    /*insert into robot (id, name, repository_part_id, ip, port, time_load, time_unload, color_fill, color_line, default_track_id, arrow_color, arrow_line_thikness, acceleration, braking_distance, braking, port_emu, current_track_id, state, cmd_error_descr, error_info_run_count, error_command_run_count, command_inner_id, letter, current_track_npp, command_rp_id, command_inner_assigned_id)
    select id, name, repository_part_id, ip, port, time_load, time_unload, color_fill, color_line, default_track_id, arrow_color, arrow_line_thikness, acceleration, braking_distance, braking, port_emu, current_track_id, state, cmd_error_descr, error_info_run_count, error_command_run_count, command_inner_id, letter, current_track_npp, command_rp_id, command_inner_assigned_id
    from ocil_robot where ocil_id=oid;*/

    update track  t
    set locked_by_robot_id=(select locked_by_robot_id from ocil_track where ocil_id=oid and id=t.id);

    insert into track_order (id, date_time_create, robot_id, repository_part_id, npp_from, npp_to, direction)
    select id, date_time_create, robot_id, repository_part_id, npp_from, npp_to, direction
    from ocil_track_order where ocil_id=oid;

    update robot set default_track_id = current_track_id;

    commit;
    return rd;
  end if;
end;

--- пометить ячейку как свободную
procedure mark_cell_as_free(cid in number, container_id_ in number, robot_id_ in number) is
  crec cell%rowtype;
  sn varchar2(300);
  cmd_id_ number default 0;
begin
  log2file('mark_cell_as_free '||cid ||' '|| container_id_ ||' '||robot_id_);
  select * into crec from cell where id=cid;
  begin
    select command_id into cmd_id_
    from command_rp where id=(select command_rp_id from robot where id=robot_id_);
  exception when others then
    null;
  end;
  if cmd_id_<>0 then -- есть команда, от имени которой разблокировать
    cell_unlock_from_cmd(cid,cmd_id_);
  end if;
  update cell
  set
    is_full=is_full-1,
    blocked_by_ci_id =0,
    container_id=0
  where id=cid;
  update container
  set
    cell_id=0,
    robot_id=robot_id_,
    location=3
  where id=container_id_;
  update robot set container_id=container_id_ where id=robot_id_;
  if crec.hi_level_type=7 then
    add_shelving_need_to_redraw(crec.shelving_id);
    sn:= crec.sname;
    select * into crec from cell where sname=sn and hi_level_type=8;
    if cmd_id_ <>0 then -- есть команда, от имени которой разблокировать
      cell_unlock_from_cmd(crec.id,cmd_id_);
    end if;
    update cell
    set
      is_full=is_full-1,
      blocked_by_ci_id =0,
      container_id=0
    where id=crec.id;
  end if;
  add_shelving_need_to_redraw(crec.shelving_id);
end;

-- добавить стеллаж к списку для перерисования
procedure add_shelving_need_to_redraw(shelving_id_ number) is 
begin
    begin
      insert into shelving_need_to_redraw (shelving_id )
      values(shelving_id_);
    exception when others then
      null;
    end;
end;

-- пометить ячейку как полную
procedure mark_cell_as_full(cid in number,container_id_ in number, robot_id_ in number) is
  crec cell%rowtype;
  sn varchar2(300);
begin
  select * into crec from cell where id=cid;
  update cell set is_full=is_full+1, blocked_by_ci_id =0 , container_id=container_id_
  where id=cid;
  update container
  set
    cell_id=cid,
    robot_id=0,
    location=1
  where id=container_id_;
  update robot set container_id=0 where id=robot_id_;
  if crec.hi_level_type=8 then
    add_shelving_need_to_redraw(crec.shelving_id);
    sn:= crec.sname;
    select * into crec from cell where sname=sn and hi_level_type=7;
    update cell set is_full=is_full+1, blocked_by_ci_id =0 , container_id=container_id_
    where id=crec.id;
    update container
    set
      cell_id=crec.id,
      location=1
    where id=container_id_;
  end if;
  add_shelving_need_to_redraw(crec.shelving_id);

end;

-- получить соотв. стеллаж на другом подскладе
FUNCTION get_corr_shelving_id(shid in number) return number is
begin
  for corr in (select shelving_id from cell
               where
                  sname in
                    (select sname from cell where shelving_id=shid )
                  and shelving_id<>shid
                  and hi_level_type in (6,7,8)
               ) loop
    return corr.shelving_id;
  end loop;
  return 0;
end;

-- есть ли ошибочные ячейки в стеллаже?
function shelving_has_error_cell(shid in number) return number is
  cnt number;
begin
  select count(*) into cnt from cell where shelving_id=shid and is_error=1;
  if cnt=0 then
    return 0;
  else
    return 1;
  end if;
end;

-- перевод секунд в дни
function get_sec(ss in number) return float is
begin
  if nvl(ss,0)=0 then
     return 0;
  else
     return ss / (24*3600);
  end if;
end;

-- путь свободен?
function is_free_way(rid number,rnpp number,gnpp number, dir number,maxnpp number,rpid number) return boolean is
  ctr number;
  has_pregr boolean;
  lid number;
begin
  ctr:=rnpp;
  has_pregr:=false;
  loop
    select locked_by_robot_id into lid from track where repository_part_id=rpid and npp=ctr;
    if lid not in (rid,0) then
      has_pregr:=true;
    end if;
    exit when has_pregr or ctr=gnpp;
    if dir=1 then
      if ctr=maxnpp then
        ctr:=0;
      else
        ctr:=ctr+1;
      end if;
    else
      if ctr=0 then
        ctr:=maxnpp;
      else
        ctr:=ctr-1;
      end if;
    end if;
  end loop;
  return not has_pregr;
end;

-- взять направление для юстировки
function get_ust_cell_dir(rid number, gtid in number) return number is
  rnpp number;
  rpid number;
  gnpp number;
  maxnpp number;
  d1 number;
  d0 number;
  ano_rid number;
  is_ano_r_busy boolean;
  cnt number;
begin
  begin
    ano_rid:=get_another_robot_id(rid);
    select count(*) into cnt from command
    where robot_id=ano_rid and state in (0,1,3);
    is_ano_r_busy:=(cnt<>0);
  exception when others then
    is_ano_r_busy:=false;
  end;
  select current_track_npp, repository_part_id
  into rnpp, rpid from robot where id=rid;
  select npp into gnpp from track where id=gtid;
  select max_npp into maxnpp from repository_part where id=rpid;
  if gnpp=rnpp then
    return 0;
  elsif gnpp>rnpp then -- цель более текущего
    d1:=gnpp-rnpp;
    d0:=rnpp+(maxnpp-gnpp);
  else -- текущее более цели
    d0:=rnpp-gnpp;
    d1:=gnpp+(maxnpp-rnpp);
  end if;
  if d1<d0 then
    if not is_ano_r_busy then
      return 1;
    else -- робот второй тоже работает - смотрим, а нельзя ли объехать
      if is_free_way(rid,rnpp,gnpp,1,maxnpp,rpid) then
        return 1;
      elsif is_free_way(rid,rnpp,gnpp,0,maxnpp,rpid) then
        return 0;
      else
        return 1;
      end if;

    end if;
  else
    if not is_ano_r_busy then
      return 0;
    else -- робот второй тоже работает - смотрим, а нельзя ли объехать
      if is_free_way(rid,rnpp,gnpp,0,maxnpp,rpid) then
        return 0;
      elsif is_free_way(rid,rnpp,gnpp,1,maxnpp,rpid) then
        return 1;
      else
        return 1;
      end if;
    end if;
  end if;

end;

-- получить ячейки для юстировки
function get_cells_for_ustirovka(rp_id number,nppfrom number, nppto number) return varchar2 is
  res varchar2(4000) default '';
begin
  for cc in (select * from cell t
             where repository_part_id=rp_id and is_error=1
                   and hi_level_type in (1,10)
                   and track_npp between nppfrom and nppto
             order by track_npp, to_number(substr(t.sname,1,3))) loop
    if res is null then
      res:=cc.sname;
    else
      res:=res||','||cc.sname;
    end if;
  end loop;
  return res;
end;

-- получить ячейки для юстировки короткий
function get_cells_for_ustirovka_short(rp_id number,nppfrom number, nppto number) return varchar2 is
  res varchar2(4000) default '';
begin
  for cc in (select * from cell t
             where repository_part_id=rp_id and is_error=1
                   and hi_level_type in (1,10)
                   and track_npp between nppfrom and nppto
                   and to_number(substr(sname,1,3))=4
             order by track_npp, to_number(substr(t.sname,1,3))) loop
    if res is null then
      res:=cc.sname;
    else
      res:=res||','||cc.sname;
    end if;
  end loop;
  return res;
end;

-- отменить все команды верификации
procedure cancel_all_verify_cmd is
begin
  delete from track_order
  where robot_id in (select robot_id from command where command_type_id=19 and state in (0,1,3));
  update robot
  set command_rp_id=0
  where id in (select robot_id from command where command_type_id=19 and state in (0,1,3)) ;
  update sarmat.command set state=2 where command_type_id=19 and state in (0,1,3);
  commit;
  update sarmat.command set state=2 where
  command_type_id=23 and state in (0,1,3);
  commit;
end;

-- разблокируем все, заблокированное текущим роботом кроме расстояния вокруг робота
procedure unlock_all_not_ness(rid in number) is
  ct number;
  cnt number;
begin
  for rr in (select r.id, r.current_track_npp npp, rp.max_npp, repository_type rt,
             rp.id rp_id,  rp.spacing_of_robots sor
             from robot r, repository_part rp
             where r.id=rid and rp.id=r.repository_part_id) loop
    -- разблокируем все, занятое текущим роботом
    update track set locked_by_robot_id=0 where locked_by_robot_id=rid;
    -- блокируем вперед
    ct:=rr.npp; cnt:=0;
    loop
      update track set locked_by_robot_id=rid
      where npp=ct and repository_part_id=rr.rp_id;
      cnt:=cnt+1;
      if ct>=rr.max_npp then
        if rr.rt=1 then
          ct:=0;
        else
          exit;
        end if;
      else
        ct:=ct+1;
      end if;
      exit when cnt>rr.sor;
    end loop;
    -- блокируем назад
    ct:=rr.npp; cnt:=0;
    loop
      update track set locked_by_robot_id=rid
      where npp=ct and repository_part_id=rr.rp_id;
      cnt:=cnt+1;
      if ct<=0 then
        if rr.rt=1 then
          ct:=rr.max_npp;
        else
          exit;
        end if;
      else
        ct:=ct-1;
      end if;
      exit when cnt>rr.sor;
    end loop;
  end loop;
end;

-- заблокировать ячейку командой
procedure cell_lock_by_cmd(cid number,cmd_id_ number) is
begin
  insert into cell_cmd_lock(cell_id,cmd_id) values(cid,cmd_id_);
end;

-- не перезаблокирование ли ячейки командами?
function is_cell_over_locked(cid number) return number is
  cnt number;
  crec cell%rowtype;
begin
  select count(*) into cnt from cell_cmd_lock where cell_id=cid;
  if cnt=0 then
    return 0;
  else
    select * into crec from cell where id=cid;
    if cnt>=crec.max_full_size then
      return 1;
    else
      return 0;
    end if;
  end if;

end;


-- заблокирована ли ячейка командой?
function is_cell_cmd_locked(cid number) return number is
  cnt number;
  cfull number;
begin
  select count(*) into cnt from cell_cmd_lock where cell_id=cid;
  select is_full into cfull from cell where id=cid;
  if cnt<cfull or cnt=0 then
    return 0;
  else
    return 1;
  end if;

end;

-- разблокируем ячейку от команды
procedure cell_unlock_from_cmd(cid number,cmd_id_ number) is
  cnt number;
begin
  log2file('cell_unlock_from_cmd cmd_id='||cmd_id_ ||' cid='||cid);
  select count(*) into cnt from cell_cmd_lock where cell_id=cid and cmd_id=cmd_id_;
  if cnt=0 then
    log2file('Unlock Error! Its not cell_lock w cell_id='||cid||' and cmd_id='||cmd_id_ );
  else
    delete from cell_cmd_lock where cell_id=cid and cmd_id=cmd_id_;
  end if;
end;


-- возвращает 1, если можно еще дать команду в эту ячейку (проверяет is_full и блокировки)
function is_cell_accept_enable(cfull number,cfullmax number,cid number) return number is
  cnt number;
begin
  if cfull>=cfullmax then
    -- и так полон
    return 0;
  else
    -- считаем сколько блокировок
    select count(*) into cnt from cell_cmd_lock where cell_id=cid;
    if (cnt+cfull)>=cfullmax then
      return 0;
    else
      return 1;
    end if;

  end if;
end;

-- сколько еще может влезть коман в ячейку
function empty_cell_capability(cfull number,cfullmax number,cid number) return number is
  cnt number;
begin
  if cfull=cfullmax then
    return 0;
  else
    -- считаем сколько блокировок
    select count(*) into cnt from cell_cmd_lock where cell_id=cid;
    if cnt+cfull>=cfullmax then
      return 0;
    else
      return cfullmax-(cnt+cfull);
    end if;
  end if;
end;


-- получить максимальный приоритет активной команды
function get_max_cmd_priority return number is
  cnt number;
  res number;
begin
  select count(*) into cnt from command
  where state in (0,1,3) and command_type_id=1
        and priority<0 and priority>-1000;
  if cnt=0 then -- нет запущенных команд
    select nvl(max(priority),0) into res from command
    where command_type_id=1 and date_time_create>=trunc(sysdate) and priority<0 and priority>-1000;
    return res;
  else
    select nvl(max(priority),0) into res from command
    where command_type_id=1 and state in (0,1,3) and priority<0 and priority>-1000;
    return res;
  end if;
end;

-- тестирование исключения
procedure test_raise_wrap is
begin
  raise_application_error (-20003, 'Ошибка ', TRUE);
end;


-- посчитать идеальную цену команды перемещения контейнера
function calc_ideal_crp_cost(rp_id_ number, csrc_id number, cdest_id number) return number is
  rpt number;
  res number;
  tpos number;
  t_start_m number;
  t_stop_m number;
  res1 number;
  res2 number;
  tmp number;
  tt number;
  max_npp_ number;
  src_npp number;
  cnpp number;
  dest_npp number;
begin
  select repository_type, max_npp into rpt, max_npp_
  from repository_part where id=rp_id_;
  select (avg(time_load)+avg(time_unload))*2, avg(time_targeting) , avg(time_start_move), avg(time_stop_move)
  into res, tpos, t_start_m, t_stop_m
  from robot where repository_part_id=rp_id_;
  select track_npp into src_npp from cell where id=csrc_id;
  select track_npp into dest_npp from cell where id=cdest_id;

  if rpt=0 then -- линейный
    if src_npp=dest_npp then
      return round(res);
    elsif src_npp>dest_npp then
      select sum(length/speed) into tmp
      from track where repository_part_id=rp_id_
        and npp between dest_npp and src_npp;
      return round(res+tmp+tpos+t_start_m+t_stop_m);
    elsif src_npp<dest_npp then
      select sum(length/speed) into tmp
      from track where repository_part_id=rp_id_
        and npp between src_npp and dest_npp;
      return round(res+tmp+tpos+t_start_m+t_stop_m);
    end if;

  else -- кольцевой
    -- считаем по часовой
    if src_npp=dest_npp then
       tpos:=0;
       t_stop_m:=0;
       t_start_m:=0;
    end if;
    cnpp:=src_npp; tmp:=0;
    loop
      select length/speed into tt from track where repository_part_id=rp_id_
        and npp =cnpp;
      tmp:=tmp+tt;
      if cnpp>=max_npp_ then
        cnpp:=0;
      else
        cnpp:=cnpp+1;
      end if;
      exit when cnpp=dest_npp;
    end loop;
    res1:=tmp;
    -- считаем протиа часовой
    cnpp:=src_npp; tmp:=0;
    loop
      select length/speed into tt from track where repository_part_id=rp_id_
        and npp =cnpp;
      tmp:=tmp+tt;
      if cnpp<=0 then
        cnpp:=max_npp_;
      else
        cnpp:=cnpp-1;
      end if;
      exit when cnpp=dest_npp;
    end loop;
    res2:=tmp;
    if res2<res1 then
      return round(res+res2+tpos+t_start_m+t_stop_m);
    else
      return round(res+res1+tpos+t_start_m+t_stop_m);
    end if;
  end if;
end;

-- может ли система заснуть?
function is_hibernate return number is
  is_exit boolean;
  dlt float;
  cnt number;
begin
  is_exit:=true;
  select count(*) into cnt from command_rp where state in (0,1,3);
  if cnt>0 then
    is_exit:=false;
  end if;

  select count(*) into cnt from command_order where state in (0,1,3);
  if cnt>0 then
    is_exit:=false;
  end if;

  select count(*) into cnt from command_gas where state in (0,1,3);
  if cnt>0 then
    is_exit:=false;
  end if;

  select sysdate-max(date_time) into dlt from log;
  if dlt<1/(24*12) then
    is_exit:=false;
  end if;
  if is_exit then
    select sysdate-max(date_time_create) into dlt from command_inner t;
    if dlt<1/(24*12) then
      is_exit:=false;
    end if;
  end if;
  if is_exit then
    select sysdate-max(date_time_create) into dlt from command t;
    if dlt<1/(24*12) then
      is_exit:=false;
    end if;
  end if;
  if is_exit then
    select sysdate-max(date_time_create) into dlt from command_gas t;
    if dlt<1/(24*12) then
      is_exit:=false;
    end if;
  end if;
  if is_exit then
    select sysdate-max(date_time_create) into dlt from command_rp t;
    if dlt<1/(24*12) then
      is_exit:=false;
    end if;
  end if;
  if is_exit then
    select sysdate-max(date_time_create) into dlt from command_order t;
    if dlt<1/(24*12) then
      is_exit:=false;
    end if;
  end if;
  if is_exit then
    return 1;
  else
    return 0;
  end if;
end;

-- залоггировать состояние АСК
procedure make_bkp_stamp is
 file_handle  utl_file.file_type;
 ss varchar2(4000);
 rs varchar2(4000);
 ns number;


 PROCEDURE INIT_ss(iss varchar2) is
 begin
   ss:='';
   rs:='';
   utl_file.put_line(file_handle, iss);
 end;
 procedure handle_ss_rs is
 begin
   if ss is null then
     ss:=rs;
   else
     if length(ss)+length(rs)<1000 then
       ss:=ss||' # '||rs;
     else
       utl_file.put_line(file_handle, ss);
       ss:=rs;
     end if;
   end if;
 end;
 procedure handle_ss_rs_fin is
 begin
   if ss is not null then
     utl_file.put_line(file_handle, ss);
   end if;
 end;
begin
 -- проверяем - а может нет смысло никого бэкапирования делать, если не было команд давно
 if is_hibernate=1 then
   return;
 end if;

 select nvl(no_shift,0) into ns from repository;
 file_handle := sys.utl_file.fopen('BKP_DIR', to_char(sysdate,'ddmmyy')||
   trim(to_char(ns,'0000'))||'_stamp', 'A');
 utl_file.put_line(file_handle, '');
 utl_file.put_line(file_handle, '-------------------------------------------');
 utl_file.put_line(file_handle, to_char(systimestamp,'hh24:mi:ss.ff'));

 INIT_ss('robot');
 for rr in (select * from robot order by id)  loop
   rs:=' '||rr.id||';'||rr.state||';'||rr.command_inner_id ||';'||
   rr.current_track_npp||';'||
   rr.command_rp_id||';'||
   rr.command_inner_assigned_id||';'||
   rr.old_cur_track_npp||';'||
   to_char(rr.old_cur_date_time,'dd.mm.yy hh24:mi:ss')||';'||
   to_char(rr.last_access_date_time,'dd.mm.yy hh24:mi:ss')||';'||
   rr.container_id ;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('track');
 for rp in (select id from repository_part order by id) loop
   ss:='';
   for tr in (select locked_by_robot_id from track where repository_part_id =rp.id order by npp) loop
     if ss is null then
       ss:=tr.locked_by_robot_id;
     else
       ss:=ss||tr.locked_by_robot_id;
     end if;
   end loop;
   utl_file.put_line(file_handle, ' rp_id='||rp.id||' '||ss);
 end loop;

 INIT_ss('track_order');
 for tor in (select * from track_order  order by id) loop
   rs:=    ' '||tor.id||';'||
     to_char(tor.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
     tor.robot_id||';'||
     tor.repository_part_id||';'||
     tor.npp_from||';'||
     tor.npp_to||';'||
     tor.direction;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('cell_cmd_lock');
 for tt in (select * from cell_cmd_lock  ) loop
   rs:= ' '||tt.cell_id||';'||
     tt.cmd_id||';'||
     tt.sname;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command');
 for tt in (select * from command where state in (0,1,3)  order by id) loop
   rs:= ' '||tt.id||';'||
     tt.command_type_id||';'||
     tt.rp_src_id||';'||
     tt.cell_src_sname||';'||
     tt.rp_dest_id||';'||
     tt.cell_dest_sname||';'||
     tt.priority||';'||
     tt.state||';'||
     tt.error_code_id||';'||
     to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
     to_char(tt.date_time_end,'dd.mm.yy hh24:mi:ss')||';'||
     to_char(tt.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
     tt.command_rp_executed||';'||
     tt.container_rp_id||';'||
     tt.cell_src_id||';'||
     tt.cell_dest_id||';'||
     tt.npp_src||';'||
     tt.npp_dest||';'||
     tt.track_src_id||';'||
     tt.track_dest_id||';'||
     tt.crp_cell||';'||
     tt.command_gas_id||';'||
     tt.container_id||';'||
     tt.robot_ip||';'||
     tt.cells||';'||
     tt.robot_id||';'||
     tt.is_intermediate;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_gas');
 for tt in (select * from command_gas where state in (0,1,3)  order by id) loop
   rs:= ' '||tt.id||';'||
     tt.command_type_id||';'||
     tt.good_desc_id||';'||
     tt.good_desc_name||';'||
     tt.mass_1||';'||
     tt.mass_box||';'||
     tt.quantity_box||';'||
     tt.abc_rang||';'||
     --tt.content||';'||
     tt.rp_id||';'||
     tt.cell_name||';'||
     tt.quantity||';'||
     tt.state||';'||
     to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
     to_char(tt.date_time_end,'dd.mm.yy hh24:mi:ss')||';'||
     to_char(tt.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
     to_char(tt.time_create,'dd.mm.yy hh24:mi:ss')||';'||
     tt.container_barcode||';'||
     tt.cell_out_name||';'||
     tt.priority||';'||
     tt.container_cell_name||';'||
     tt.container_rp_id||';'||
     tt.container_id||';'||
     tt.zone_letter||';'||
     tt.quantity_out||';'||
     tt.quantity_promis||';'||
     tt.reserved||';'||
     to_char(tt.last_analized ,'dd.mm.yy hh24:mi:ss');
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_gas_cell_in');
 for tt in (select cgc.* from command_gas cg, command_gas_cell_in cgc
            where state in (0,1,3) and cgc.command_gas_id=cg.id  order by id) loop
   rs:= ' '||tt.command_gas_id||';'||
      tt.cell_id||';'||
      tt.sname||';'||
      tt.track_npp;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_gas_out_container');
 for tt in (select cgc.* from command_gas cg, command_gas_out_container cgc
            where state in (0,1,3) and cgc.cmd_gas_id=cg.id  order by id) loop
   rs:= ' '||tt.cmd_gas_id||';'||
      tt.container_id||';'||
      tt.container_barcode||';'||
      tt.good_desc_id||';'||
      tt.quantity||';'||
      tt.cell_name;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_gas_out_container_plan');
 for tt in (select cgc.* from command_gas cg, command_gas_out_container_plan cgc
            where state in (0,1,3) and cgc.cmd_gas_id=cg.id  order by id) loop
   rs:= ' '||tt.cmd_gas_id||';'||
      tt.container_id||';'||
      tt.quantity_all||';'||
      tt.quantity_to_pick||';'||
      tt.quantity_was_picked;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_inner');
 for tt in (select * from command_inner
            where state in (0,1,3)  order by id) loop
   rs:= ' '||tt.id||';'||
      tt.command_type_id||';'||
      tt.rp_id||';'||
      tt.cell_src_sname||';'||
      tt.cell_dest_sname||';'||
      tt.state||';'||
      tt.error_code_id||';'||
      to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
      to_char(tt.date_time_end,'dd.mm.yy hh24:mi:ss')||';'||
      tt.command_rp_id||';'||
      to_char(tt.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
      tt.robot_id||';'||
      tt.command_to_run||';'||
      tt.track_src_id||';'||
      tt.track_dest_id||';'||
      tt.direction||';'||
      tt.cell_src_id||';'||
      tt.cell_dest_id||';'||
      tt.npp_src||';'||
      tt.npp_dest||';'||
      tt.track_id_begin||';'||
      tt.track_npp_begin||';'||
      tt.cell_sname_begin||';'||
      tt.problem_resolving_id||';'||
      tt.container_id;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_order');
 for tt in (select * from command_order
            where state in (0,1,3)  order by id) loop
   rs:= ' '||tt.id||';'||
       tt.command_type_id||';'||
       tt.good_desc_id||';'||
       tt.rp_id||';'||
       tt.cell_name||';'||
       tt.quantity||';'||
       tt.state||';'||
       to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
       to_char(tt.date_time_end,'dd.mm.yy hh24:mi:ss')||';'||
       to_char(tt.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
       to_char(tt.time_create,'dd.mm.yy hh24:mi:ss')||';'||
       tt.container_barcode||';'||
       tt.order_number||';'||
       tt.group_number||';'||
       tt.point_number||';'||
       tt.priority||';'||
       tt.command_gas_id||';'||
       tt.quantity_from_gas||';'||
       tt.cmd_order_id||';'||
       tt.quantity_promis||';'||
       tt.notes;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_order_cell_in');
 for tt in (select * from command_order co, command_order_cell_in coci
            where state in (0,1,3) and coci.command_order_id =co.id  order by id) loop
   rs:= ' '||tt.command_order_id||';'||
        tt.cell_id||';'||
        tt.sname||';'||
        tt.track_npp;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_order_out_container');
 for tt in (select coci.* from command_order co, command_order_out_container coci
            where co.state in (0,1,3) and coci.cmd_order_id =co.id  order by id) loop
   rs:= ' '||tt.cmd_order_id||';'||
        tt.container_id||';'||
        tt.container_barcode||';'||
        tt.good_desc_id||';'||
        tt.quantity||';'||
        tt.order_number||';'||
        tt.group_number||';'||
        tt.cell_name||';'||
        tt.point_number||';'||
        tt.state||';'||
        tt.command_gas_id;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 INIT_ss('command_rp');
 for tt in (select * from command_rp
            where state in (0,1,3)  order by id) loop
   rs:= ' '||tt.id||';'||
        tt.command_type_id||';'||
        tt.rp_id||';'||
        tt.cell_src_sname||';'||
        tt.cell_dest_sname||';'||
        tt.priority||';'||
        tt.state||';'||
        tt.error_code_id||';'||
        to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
        to_char(tt.date_time_end,'dd.mm.yy hh24:mi:ss')||';'||
        to_char(tt.date_time_create,'dd.mm.yy hh24:mi:ss')||';'||
        tt.command_id||';'||
        tt.command_inner_executed||';'||
        tt.robot_id||';'||
        tt.direction_1||';'||
        tt.direction_2||';'||
        tt.substate||';'||
        tt.track_src_id||';'||
        tt.track_dest_id||';'||
        tt.sql_text_for_group||';'||
        tt.cell_src_id||';'||
        tt.cell_dest_id||';'||
        tt.npp_src||';'||
        tt.npp_dest||';'||
        tt.calc_cost||';'||
        tt.priority_inner||';'||
        tt.command_inner_last_robot_id||';'||
        to_char(tt.time_create,'dd.mm.yy hh24:mi:ss')||';'||
        tt.is_to_free||';'||
        tt.container_id||';'||
        tt.ideal_cost;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;


 INIT_ss('container_collection');
 for tt in (select * from container_collection
            where state =0  order by id) loop
   rs:= ' '||tt.id||';'||
        to_char(tt.date_time_begin,'dd.mm.yy hh24:mi:ss')||';'||
        tt.container_id||';'||
        tt.state||';'||
        --tt.good_desc_id||';'||
        tt.cmd_gas_id||';'||
        tt.container_barcode||';'||
        tt.cell_name;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;


 INIT_ss('container_collection_content');
 for tt in (select ccc.* from container_collection cc, container_collection_content ccc
            where state =0  and ccc.cc_id=cc.id order by id) loop
   rs:= ' '||tt.cc_id||';'||
        tt.cmd_order_id||';'||
        tt.quantity_need||';'||
        tt.quantity_real||';'||
        tt.quantity_deficit||';'||
        tt.good_desc_id;
   handle_ss_rs;
 end loop;
 handle_ss_rs_fin;

 utl_file.fclose(file_handle);
end;


-- залоггировать состояние с товарами
procedure make_bkp_good is
 file_handle  utl_file.file_type;
 ss varchar2(32000);
 cs varchar2(300);
begin
 file_handle := sys.utl_file.fopen('BKP_DIR', 'good', 'A');
 utl_file.put_line(file_handle, '');
 utl_file.put_line(file_handle, '-------------------------------------------');
 utl_file.put_line(file_handle, to_char(systimestamp,'hh24:mi:ss.ff'));

 utl_file.put_line(file_handle, 'good_desc');
 for tt in (select * from good_desc order by id) loop
   utl_file.put_line(file_handle, ' '||tt.id||';'||
     tt.quantity||';'||
     tt.quantity_reserved);
 end loop;

 utl_file.put_line(file_handle, 'cell');
 ss:='';
 for tt in (select * from cell) loop
   cs:= ' '||tt.id||';'||
     tt.is_full||';'||
     tt.blocked_by_ci_id||';'||
     tt.container_id;
   if ss is null then
     ss:=cs;
   elsif length(ss)<1000 then
     ss:=ss||'#'||cs;
   else
     utl_file.put_line(file_handle, ss);
     ss:='';
   end if;
 end loop;
 if ss is not null then
   utl_file.put_line(file_handle, ss);
 end if;

 utl_file.fclose(file_handle);

end;

-- строку в журнал
procedure bkp_to_file(fname in varchar2, ss varchar2) is
 file_handle  utl_file.file_type;
 ns number;
 ssn varchar2(4000); 
 sc varchar2(250); 
begin
 if bkp_to_file_active=0 then 
   return;
 end if;  
 select nvl(no_shift,0) into ns from  repository;
 file_handle := sys.utl_file.fopen('BKP_DIR', to_char(sysdate,'ddmmyy')||'_'||
   trim(to_char(ns,'0000'))||'_'||fname, 'A');
 ssn:=to_char(systimestamp,'hh24:mi:ss.ff')||';'||ss;
 loop  
   if length(ssn)<=250 then
     sc:=ssn;
     ssn:='';
   else
     sc:=substr(ssn,1,250);
     ssn:=substr(ssn,251);
   end if;
   utl_file.put_line(file_handle, sc);
   exit when ssn is null;
 end loop; 
 utl_file.fclose(file_handle);
end;

-- взять список иного товара, что лежит в контейнере
function get_another_gd(cnt_id number, gd_id_ varchar2, max_size number default 4000) return varchar2 is
  res varchar2(4000);
  pp varchar2(300);
begin
  res:='';
  for cc in (select gd.name, cc.quantity, cc.gdp_id
             from container_content cc, good_desc gd
             where cc.container_id=cnt_id and cc.good_desc_id=gd.id
             and gd.id<>gd_id_ AND cc.quantity>0
             order by gd.name) loop
    if length(res)>=4000-250 then
      res:=res||chr(13)||'..';
      exit;
    end if;
    pp:='';
    if cc.gdp_id is not null then
      for gdp in (select * from gd_party where id=cc.gdp_id) loop
        pp:='('||gdp.pname||')';
        exit;
      end loop;
    end if;
    if res is null then
      res:=cc.name||'='||cc.quantity||pp||chr(13);
    else
      if length(cc.name||'='||cc.quantity||chr(13))+length(res)>max_size then
        res:=res||'...';
        exit;
      else
        res:=res||cc.name||'='||cc.quantity||pp||chr(13);
      end if;
    end if;
  end loop;
  return res;

end;

-- получить статус ячейки хранения
function get_cell_storage_state(is_full in number, is_error in number, is_realy_bad in number) return number is
  -- =1 - рабочая и пустая
  -- =2 - реально плохая ячейка, разблокировки не подлежит
  -- =3 - рабочая и полная
  -- =4 - пока еще неотюстированная ячейка
begin
  if is_error=0 then
    if is_full=0 then
      return 1;
    else
      return 3;
    end if;
  else
    if is_realy_bad=0 then
      return 4;
    else
      return 2;
    end if;
  end if;
end;


-- преобразовать строку в число
function to_number_my(ss in varchar2) return number is
  Result number;
begin
  return(to_number(ss));
  exception when others then return(0);
end to_number_my;

-- ячейка полностью проверена?
function is_cell_full_check return number is
begin
  for rr in (select ignore_full_cell_check  from repository) loop
    if nvl(rr.ignore_full_cell_check,0)=1 then
       return 0;
    else
       return 1;
    end if;
  end loop;
end;

-- путь свободен для робота?
function is_way_free_for_robot(rid_ number, npp_from number, npp_to number) return number is
  npp_ number;
  npp_exit number;
begin
  for rob in (select * from robot where id=rid_) loop
      npp_exit:=obj_rpart.inc_spacing_of_robots(npp_to, 1, 1, rob.repository_part_id);
      npp_:=npp_from;
      loop
        for tr in (select locked_by_robot_id lbr from track where npp=npp_ and repository_part_id=rob.repository_part_id) loop
          if tr.lbr not in (rid_ ,0) then
            return 0;
          end if;
        end loop;
        npp_:=obj_rpart.inc_spacing_of_robots(npp_, 1, 1, rob.repository_part_id);
        exit when npp_=npp_exit;
      end loop;
  end loop;
  return 1;
end;

-- устаревшая функция перевода робота в режим починки
function set_robot_mode_to_repair(rid_ number, npp_rep number, param number) return varchar2 is
  npp1 number;
  npp2 number;
  tl1 number;
  tid_rep number;
  cinew number;
  was_load number;
  bri number;

  procedure cancel_command(cid_ number, crp_id_ number) is
  begin
    update command_inner -- типа успешно завершаем
    set state=2
    where id=cid_;
    update command_rp
    set robot_id=null, state=1
    where id=crp_id_;
  end;

  procedure finish_command_by_hand(cid_ number, crp_id_ number) is
    cinew number;
  begin
    update command_inner -- типа успешно завершаем
    set state=5, date_time_end=sysdate
    where id=cid_;
    for crp in (select * from command_rp where id=crp_id_) loop
      insert into command_inner(command_type_id, rp_id, cell_dest_sname, state, command_rp_id, robot_id, command_to_run, track_dest_id, direction,
          cell_dest_id, npp_dest, track_id_begin, track_npp_begin, container_id,
          cell_src_id, date_time_begin, date_time_end, track_src_id, npp_src, cell_sname_begin)
      values(5, crp.rp_id, crp.cell_dest_sname, 0, crp.id, crp.robot_id,'UNLOAD '||crp.cell_dest_sname, crp.track_dest_id,1,
          crp.cell_dest_id, crp.npp_dest, 0, 0,crp.container_id,
          0 , sysdate, sysdate,0,0, crp.cell_src_sname)
      returning id into cinew;
      update command_inner set state=1 where id=cinew;
      update command_inner set state=3 where id=cinew;
      update command_inner set state=5 where id=cinew;
    end loop;
  end;

begin
  for rr in (select is_work  from repository) loop
    if rr.is_work=1 then
      return 'Operation is possible only for ASK in PAUSE mode!';
    end if;
  end loop;
  for rob in (select * from robot where id=rid_) loop

    for rp in (select id, spacing_of_robots sorb, max_npp from repository_part where id=rob.repository_part_id) loop


      if rob.state=6 then
        return 'Robot is already in repair mode!';
      end if;
      for tr in (select * from track where repository_part_id=rob.repository_part_id and npp=npp_rep) loop
        tid_rep:=obj_rpart.get_track_id_by_robot_and_npp(rid_, npp_rep);

        npp1:=obj_rpart.inc_spacing_of_robots(npp_rep, 1, rp.sorb, rp.id);
        npp2:=obj_rpart.inc_spacing_of_robots(npp_rep, obj_rpart.get_another_direction(1), rp.sorb, rp.id);
        if is_way_free_for_robot(rid_, npp2, npp1)<>1 then
          return 'Desired area is locked by another robot!';
        end if;

        -- делаем действия
        -- были ли команда?
        if nvl(rob.command_inner_id,0)>0 then
          for ci in (select * from command_inner where id=nvl(rob.command_inner_id,0)) loop

            if ci.command_type_id=5 then -- unload
               update command_inner -- типа успешно завершаем
               set state=5, date_time_end=sysdate
               where id=ci.id;

            elsif ci.command_type_id=6 then -- move
               if nvl(ci.command_rp_id,0)=0 then -- простая команда освобождения пути
                 update command_inner -- типа успешно завершаем
                 set state=5, date_time_end=sysdate
                 where id=ci.id;
               else -- есть команда command_rp - анализируем дальше
                 was_load:=0;
                 for cmd in (select * from command_inner t
                            where t.command_rp_id=nvl(ci.command_rp_id,0) and robot_id=rid_ and state=5 and command_type_id in (4,5)
                            order by id desc) loop
                   was_load:=1;
                 end loop;
                 if was_load=1 then -- была загрузка, значит, вручную доделали, прописываем
                   finish_command_by_hand(ci.id, ci.command_rp_id);
                 else -- не было еще загрузки, отменяем команду
                   cancel_command(ci.id, ci.command_rp_id);
                 end if;
               end if;

            elsif ci.command_type_id=4 then -- load
               if param=1 then -- контейнер все еще в ячейке
                 cancel_command(ci.id, ci.command_rp_id);
               else -- контейнер на роботе - значит, вручную переместили уже
                 finish_command_by_hand(ci.id, ci.command_rp_id);
               end if;
            end if;
          end loop;
        end if;

        -- универсальные действия независимо от
        update track set locked_by_robot_id=0 where locked_by_robot_id=rid_;
        insert into robot_trigger_ignore(robot_id) values(rid_);
        --ie_tools.disable_table_trigger('ROBOT');

        update robot
        set state=6,
            current_track_id=tid_rep,
            current_track_npp=npp_rep,
            command_rp_id=null,
            command_inner_assigned_id=0,
            wait_for_problem_resolve=0,
            command_inner_id=Null,
            old_cur_track_npp=npp_rep
        where id=rid_;
        delete from robot_trigger_ignore where robot_id=rid_;
        --ie_tools.enable_table_trigger('ROBOT');
        --function Try_Track_Lock(rid_ number, npp_to_ number, dir_ number ,  IsIgnoreBufTrackOrder boolean, barrier_robot_id out number) return number; -- очень хитрая функция блокировки трека - подробности см. в исходниках ф-ии

        tl1:=obj_rpart.Try_Track_Lock(rid_, npp_rep,1,true,bri );
        if tl1<>-1 then
          rollback;
          return 'Attempt to lock new track area was failed!';
        end if;
        commit;
        delete from track_order where robot_id=rid_;
        commit;

        return 'OK';
      end loop;
      return 'Track '||npp_rep||' is not in repository '||rob.repository_part_id||'!';

    end loop;
    return 'Repository part is not found for robot!';
  end loop;
  return 'Robot ID='||rid_||' is not found!';

end;

-- устаревшая функция вывода робота из починки
function set_robot_repair_done(rid_ number) return varchar2 is
begin
  update robot set state=0 where id=rid_;
  commit;
  return 'OK';
end;

-- получить список доп. параметров для решения проблемы
function get_robot_stop_param(rid_ number) return number is
begin
  for rr in (select * from robot where id=rid_) loop
    if nvl(rr.command_inner_id,0)<>0 then
     for cmd in (select * from command_inner where id=rr.command_inner_id) loop
       if cmd.command_type_id=5 then -- UNLOAD
         return 1; -- напоминание, что нужно вручную завершить операцию
       elsif cmd.command_type_id=4 then -- LOAD
         return 2; -- напоминание, что нужно спросить о том, ячейка на роботе или нет?
       elsif cmd.command_type_id=6 then -- MOVE
         if nvl(cmd.command_rp_id,0)=0 then -- просто перемещение для освбождения пути - нет необходимости в доп. огр.
           return 0;
         else -- есть команда command_rp для move
           for ci in (select * from command_inner
                      where command_rp_id=nvl(cmd.command_rp_id,0) and robot_id=rid_ and state=5 and command_type_id in (4,5)
                      order by id desc) loop
             if ci.command_type_id=4 then -- load уже ранее произведен был
               return 1; -- напоминание про необходимость завершить операцию
             elsif ci.command_type_id=5 then -- unload
               null; -- иакого быть не может
             end if;
           end loop;
           return 0; -- не успели напакостить
         end if;
       end if;
     end loop;
    end if;

  end loop;
  return 0; -- нет никаких доп. моментов
end;

-- изменяем кол-во товара в контейнере
procedure  change_cc_qty(cnt_id_ number, gd_id_ varchar2, dqty number, gdp_id_ number) is
  ipc number;
  cnt number;
begin
  select is_party_calc into ipc from repository;
  if nvl(ipc,0)=0 then  -- нет учета по партиям
     select count(*) into cnt from container_content
     where container_id = cnt_id_ and good_desc_id=gd_id_;
     if cnt=0 then -- нету такой позиции в контейнере
       if dqty>0 then --увеличивание кол-ва - добавляем
         insert into container_content(container_id, good_desc_id, quantity)
         values(cnt_id_, gd_id_, dqty);
       else -- не может быть ументшение того, чего нет
         raise_application_error (-20003, 'Container content qty must be positive!', TRUE);
       end if;
     else -- уже есть такая позиция
       update container_content
       set quantity= quantity+dqty
       where container_id = cnt_id_ and good_desc_id=gd_id_;
     end if;
  else -- есть учет по партиям
    if dqty>0 then  -- увеличение
      if nvl(gdp_id_,0)=0 then -- учет по партиям, но явно партия для увеличения не указана
        select count(*) into cnt from container_content
        where container_id = cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=0;
        if cnt=0 then -- нет без партии товара
         insert into container_content(container_id, good_desc_id, quantity, gdp_id )
         values(cnt_id_, gd_id_, dqty, null);
        else -- есть без партии товар
          update container_content
          set quantity= quantity+dqty
          where container_id = cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=0;
        end if;
      else  --учет по партиям, и явно партия для увеличения указана
        select count(*) into cnt from container_content
        where container_id = cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=nvl(gdp_id_,0);
       if cnt=0 then -- нету такой позиции в контейнере
         insert into container_content(container_id, good_desc_id, quantity, gdp_id)
         values(cnt_id_, gd_id_, dqty, gdp_id_);
       else -- уже есть такая позиция
         update container_content
         set quantity= quantity+dqty
         where container_id = cnt_id_ and good_desc_id=gd_id_ and gdp_id_=gdp_id;
       end if;
      end if;
    else -- уменьшение
      if nvl(gdp_id_,0)=0 then -- учет по партиям, но явно партия для увеличения не указана
        select count(*) into cnt from container_content
        where container_id = cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=0;
        if cnt=0 then -- нет без партии товара
         raise_application_error (-20003, 'Container content qty must be positive!', TRUE);
        else -- есть без партии
          update container_content
          set quantity= quantity+dqty
          where container_id = cnt_id_ and good_desc_id=gd_id_ and gdp_id_=gdp_id and nvl(gdp_id,0)=0;
        end if;
      else  --учет по партиям, и явно партия для уменьшения  указана
        select count(*) into cnt from container_content
        where container_id = cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=nvl(gdp_id_,0);
        if cnt=0 then -- нет партии для уменьшения
          raise_application_error (-20003, 'Container content qty must be positive for shipment too!', TRUE);
        else -- есть и партия
          update container_content
          set quantity= quantity+dqty
          where container_id = cnt_id_ and good_desc_id=gd_id_ and gdp_id_=gdp_id and nvl(gdp_id,0)=nvl(gdp_id_,0) ;
        end if;
      end if;
    end if;
  end if;
end;

-- взять № контейнера command_inner команды по id роботу
function get_robot_ci_cnt_bc(rid_ number) return varchar2 is
begin
  for rr in (select * from robot where id=rid_) loop
    for crp in (select * from command_rp where id=rr.command_rp_id) loop
      for cc in (select * from container where id=crp.container_id) loop
        return cc.barcode;
      end loop;
    end loop;
  end loop;
  return '';
end;

-- взять № ячейки источник command_inner команды по id роботу
function get_robot_ci_cell_src(rid_ number) return varchar2 is
begin
  for rr in (select * from robot where id=rid_) loop
    for ci in (select * from command_inner where id=rr.command_inner_id) loop
      for cc in (select * from cell where id=ci.cell_src_id) loop
        return cc.sname;
      end loop;
    end loop;
  end loop;
  return '';
end;

-- взять № ячейки назначения command_inner команды по id роботу
function get_robot_ci_cell_dst(rid_ number) return varchar2 is
begin
  for rr in (select * from robot where id=rid_) loop
    for ci in (select * from command_inner where id=rr.command_inner_id) loop
      for crp in (select * from command_rp where id=ci.command_rp_id) loop
        for cc in (select * from cell where id=crp.cell_dest_id) loop
          return cc.sname;
        end loop;
      end loop;
    end loop;
  end loop;
  return '';
end;

-- получить имя робота по ID
function get_robot_name(rid_ number) return varchar2 is
begin
  for rr in (select * from robot where id=rid_) loop
    return rr.name;
  end loop;
  return '';
end;

-- мультиязычность - получить значение в зависимости от языка 
function ml_get_rus_eng_val(in_rus varchar2, in_eng varchar2) return varchar2 is
begin
  for rr in (select language from repository) loop
    if nvl(rr.language,0)=0 then
      return in_rus;
    else
      return in_eng;
    end if;
  end loop;

end;

-- мультиязычность - получить значение 
function ml_get_val(var_name_ varchar2, val_def_ varchar2) return varchar2 is
  s1 varchar2(4000);
  s2 varchar2(4000);
  s3 varchar2(4000);
  s4 varchar2(4000);
begin
  for rr in (select language from repository) loop
    if rr.language=0 then
      return val_def_;
    else
      who_called_me(s1,s2,s3,s4);
      if s4='PACKAGE BODY' then
        for mf in (select * from ml_form where upper(name)=upper(s2||'.BDY')) loop
          for mfc in (SELECT * FROM ml_form_control where ml_form_id =mf.id and upper(name)=upper(var_name_)) loop
            for mfcv in (select * from ml_form_control_val where ml_form_control_id =mfc.id and lang_id=rr.language) loop
              return mfcv.val_;
            end loop;
          end loop;
        end loop;
      else
        return val_def_;
      end if;
    end if;
  end loop;
  return val_def_;
end;

-- получить информацию о состоянии последней команды, отданной с указанного компьютера
procedure get_last_cmd(comp_name_ varchar2, cmd_name out varchar2,cmd_name_full out varchar2, dt_cr out varchar2,
                       sost out varchar2, error_ out varchar2) is
  cgid number;
begin
  error_:='0';
  for cmd in (select cmd.* from command cmd, cell cl, repository rp
              where cl.id in (cmd.cell_src_id, cmd.cell_dest_id)
                    and (trim(upper(cl.notes))=trim(upper(comp_name_)) or rp.cell_by_comp=0)
                    and cmd.date_time_create >trunc(sysdate)-50
              order by cmd.id desc) loop
    cmd_name:=ml_get_val('get_last_cmd.transfer_container','переместить контейнер');
    cmd_name_full:=cmd.cell_src_sname||'('||cmd.rp_src_id||') -> '||cmd.cell_dest_sname||'('||cmd.rp_dest_id||')';
    dt_cr:=to_char(cmd.date_time_create, 'dd.mm.yy hh24:mi');
    if cmd.state=0 then
      sost:=ml_get_val('get_last_cmd.prepared','готовится');
    elsif cmd.state=1 then
      sost:=ml_get_val('get_last_cmd.received','получена АСК');
    elsif cmd.state=3 then
      sost:=ml_get_val('get_last_cmd.running','запущена');
    elsif cmd.state=5 then
      sost:=ml_get_val('get_last_cmd.finished','выполнена');
    elsif cmd.state=6 then
      sost:=ml_get_val('get_last_cmd.canceled','отменена');
    elsif cmd.state=2 then
      sost:=ml_get_val('get_last_cmd.error_serious','ошибка - обратитесь к сисадмину!');
    else
      sost:=ml_get_val('get_last_cmd.undefined','неопределено');
    end if;
    for cr in (select r.* from robot r, command_inner ci, cell cl, repository rp
               where wait_for_problem_resolve=1 and command_inner_id=ci.id
                     and(
                       ci.command_type_id=4 and cl.id=cell_src_id
                       or
                       ci.command_type_id=5 and cl.id=cell_dest_id)
                     and (trim(upper(cl.notes))=trim(upper(comp_name_)) or rp.cell_by_comp=0)) loop
      sost:=ml_get_val('get_last_cmd.error_simple','Ошибка - жду решения оп-ра');
      error_:='1';
    end loop;
    if error_='0' then
      for cr in (select r.* from robot r, command_inner ci, cell cl, command cmd, command_rp crp, repository rp
                 where wait_for_problem_resolve=1 and command_inner_id=ci.id
                       and crp.command_id=cmd.id and ci.command_rp_id=crp.id
                       and cl.id in (cmd.cell_src_id,cmd.cell_dest_id)
                       and (trim(upper(cl.notes))=trim(upper(comp_name_)) or rp.cell_by_comp=0)) loop
        sost:=ml_get_val('get_last_cmd.error_serious','Ошибка - обратитесь к сисадмину!');
        error_:='2';
      end loop;
    end if;
    return;
  end loop;


  cmd_name:='-';
  cmd_name_full :='-';
  dt_cr :='-';
  sost :='-';
end;

-- сколько штук товара в контейнере?
function get_container_sum_qty(cnt_id_ number) return number is
  res number;
begin
  res:=0;
  select nvl(sum(quantity) ,0) into res from container_content where container_id=cnt_id_;
  return res;
end;

-- повторить последнюю команду оператора с компьютера
function op_last_cmd_repeat(comp_name_ varchar2) return number is
begin
  for ci in (select ci.id, pr.id prid , ci.command_type_id, r.platform_busy
             from robot r, command_inner ci, cell c, problem_resolving pr, repository rp
             where wait_for_problem_resolve=1
                   and c.id in (ci.cell_src_id, ci.cell_dest_id)
                   and pr.short_name='Retry' and pr.command_type_id=ci.command_type_id
                   and ci.id=r.command_inner_id
                   and (trim(upper(nvl(c.notes,'-')))=trim(upper(comp_name_)) or  rp.cell_by_comp=0) ) loop
    if ci.platform_busy=1 and ci.command_type_id=4 then -- типа Load повторить, а платформа уже занята
      return 0;
    end if;
    if ci.platform_busy=0 and ci.command_type_id=5 then -- типа UnLoad повторить, а платформа уже пуста
      return 0;
    end if;
    update command_inner
    set problem_resolving_id=ci.prid where id=ci.id;
    commit;
    return 1;
  end loop;
  return 0;
  exception when others then
    return 0;
end;

-- пометить последнюю команду оператора как исполненную ОК 
function op_last_cmd_mark_as_ok(comp_name_ varchar2) return number is
begin
  for ci in (select ci.id, pr.id prid, ci.command_type_id, r.platform_busy
             from robot r, command_inner ci, cell c, problem_resolving pr, repository rp
             where wait_for_problem_resolve=1
                   and c.id in (ci.cell_src_id, ci.cell_dest_id)
                   and pr.short_name='Handle' and pr.command_type_id=ci.command_type_id
                   and ci.id=r.command_inner_id
                   and (trim(upper(nvl(c.notes,'-')))=trim(upper(comp_name_))  or rp.cell_by_comp=0)) loop
    if ci.platform_busy=0 and ci.command_type_id=4 then -- типа Load успешно, а платформа пустая
      return 0;
    end if;
    if ci.platform_busy=1 and ci.command_type_id=5 then -- типа UnLoad успешно, а платформа занята
      return 0;
    end if;
    update command_inner
    set problem_resolving_id=ci.prid where id=ci.id;
    commit;
    return 1;
  end loop;
  return 0;
  exception when others then
    return 0;
end;

-- удаляем информацию по открытым формам 
procedure clear_form_opened is
begin
  delete from form_opened where user_name=user;
  commit;
end;

-- ячейка закреплена за компьютером?
function is_cell_on_comp(cid_ number, cname varchar2) return number is
begin
  for cc in (select * from cell where id=cid_ and upper(notes)=upper(cname)) loop
    return 1;
  end loop;
  return 0;
end;

-- взять числовой параметр всего АСК
function get_rp_param_number(cpn varchar2, def number default 0) return number is
begin
  for cp in (select * from repository_param where trim(upper(name))=trim(upper(cpn))) loop
    return nvl(cp.value_number,0) ;
  end loop;
  return def;
end;

-- взять строковый параметр всего АСК
function get_rp_param_string(cpn varchar2, def varchar2 default null) return varchar2 is
begin
  for cp in (select * from repository_param where trim(upper(name))=trim(upper(cpn))) loop
    return nvl(cp.value_string,0) ;
  end loop;
  return def;
end;


-- установка числового параметра АСК 
procedure set_rp_param_number(cpn varchar2, param_ number) is
begin
  for cp in (select * from repository_param where trim(upper(name))=trim(upper(cpn))) loop
    update repository_param set value_number=param_ where trim(upper(name))=trim(upper(cpn));
    commit;
    return;
  end loop;
  -- новый параметр
  insert into repository_param(name, value_number)
  values(cpn, param_);
  commit;
end;


-- ячейка достижима лишь для одного робота? (для линейных огурцов)
function cell_acc_only_1_robot(src_ number, dst_ number) return number is
begin
  for cs in (select * from cell where id=src_) loop
    for cd in (select * from cell where id=dst_) loop
         for tua in (select r.* from robot r
                     where r.repository_part_id=cs.repository_part_id
                           and nvl(work_npp_from,-1)>=0 and nvl(work_npp_to,-1)>=0
                           and cs.track_npp not between nvl(work_npp_from,-1) and nvl(work_npp_to,-1)) loop
           -- источник недостижим для робота tua.id
           for rr in  (select * from robot
                       where repository_part_id=cd.repository_part_id and id<>tua.id
                             and nvl(work_npp_from,-1)>=0 and nvl(work_npp_to,-1)>=0
                             and cd.track_npp not between nvl(work_npp_from,-1) and nvl(work_npp_to,-1)
                       ) loop
               -- цель недостижима для второго робота
               return 1;
             end loop;
         end loop;
    end loop;
  end loop;
  return 0;
end;


-- ячейка возде края №№ треков?
function is_cell_near_edge(cid_ number) return number is
begin
  for cc in (select * from cell where id=cid_) loop
    for rp in (select repository_type , num_of_robots, max_npp, spacing_of_robots
               from repository_part where id=cc.repository_part_id ) loop
      if rp.num_of_robots <>2 or rp.repository_type<>0 then
        return 0;
      else
        if cc.track_npp <= 2*rp.spacing_of_robots then
          return 1;
        elsif cc.track_npp >= rp.max_npp - 2*rp.spacing_of_robots then
          return 2;
        end if;
      end if;
    end loop;
  end loop;
  return 0;
end;

-- получить ШК контейнера, что сейчас на роботе
function get_cnt_name_on_robot(rid_ number) return varchar2 is
begin
  for rr in (select cnt.barcode from robot r, container cnt where container_id=cnt.id and r.id=rid_) loop
    return rr.barcode;
  end loop;
  return '-';
end;

-- команда перемещения робота к ячейке
procedure robot_goto_cell(rid_ number, sname_ varchar2) is
  dir number;
begin
  for tt in (select track_npp , r.repository_part_id
             from robot r, cell
             where upper(sname)=trim(upper(sname_)) and r.id=rid_
               and r.repository_part_id=cell.repository_part_id) loop
    if obj_rpart.is_poss_to_lock(rid_, tt.track_npp, 0)=1 then
       dir:=0;
    else
       dir:=1;
    end if;
    insert into command_rp(command_type_id, robot_id, direction_1,cell_dest_sname, rp_id, cell_src_sname, priority, command_id)
    values(30,rid_,dir,sname_, tt.repository_part_id,'-',1,-1);
    commit;
    return;
  end loop;
  raise_application_error (-20003, 'Error parameters for robot go to cmd', TRUE);
end;

-- преобразовать строку в число слева
function to_number_from_left(ss varchar2) return number is
  res varchar2(250);
begin
  res:=''; 
  for i in 1..length(ss) loop
    if substr(ss,i,1) in ('0','1','2','3','4','5','6','7','8','9') then
      res:=res||substr(ss,i,1);
    else
      exit;
    end if;
  end loop;
  if res is null then
    return 0;
  else
    return to_number(res);
  end if;
end;

end service;
/
