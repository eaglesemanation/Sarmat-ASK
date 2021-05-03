create or replace package body obj_rpart is  -- объект подсклада (огурца)

-- возвращает имя файла журнала
function Get_Log_File_Name(rp_id_ in number) return varchar2 is
begin
  return 'rp_ora_'||rp_id_||'_'||to_char(sysdate,'ddmmyy')||'.log';
end;

-- процедура ведения журнала
procedure Log(rp_id_ number, txt_ varchar2) is
 file_handle__  utl_file.file_type;
 fn__ varchar2(300);
begin
 --return;
 fn__:=Get_Log_File_Name(rp_id_);
 file_handle__ := sys.utl_file.fopen('LOG_DIR', fn__, 'A');
 utl_file.put_line(file_handle__, to_char(systimestamp,'hh24:mi:ss.ff')||' '||txt_);
 utl_file.fclose(file_handle__);
end;


-- **********************************************************************
-- ** Всяческие служебные функции

-- получить иное, чем указанное, направление движения робота
function Get_Another_Direction(direction_ in number) return number is
begin
  if direction_=1 then
     return 0;
  else
     return 1;
  end if;
end;

-- получить имя ячейки по ID трека (для команды робота move)
function Get_Cell_Name_By_Track_ID(track_id_ in number) return varchar2 is
  res__ varchar2(100);
begin
  select cell_sname into res__
  from track
  where
    id=track_id_;
  return res__;
end;

-- получить id свободной транзитной ячейки для передач внутри одного огурца
function get_transit_1rp_cell(rpid_ number) return number is
begin
  for ncl in (select cell.* from cell
                    where
                    repository_part_id=rpid_
                    and is_full=0 and nvl(blocked_by_ci_id,0)=0
                    and service.is_cell_over_locked(cell.id)=0
                    and nvl(is_error,0)=0
                    and hi_level_type=obj_ask.CELL_TYPE_TRANSIT_1RP) loop
    return ncl.id;
  end loop;
  return 0;
end;

-- получить ID робота по ID подсклада (только для огурцов с одним роботом)
function get_robot_by_rp(rpid_ number) return number is
  errmm__ varchar2(1000);
begin
  for rp in (select num_of_robots nor from repository_part where id=rpid_) loop
    if rp.nor>1 then
          errmm__:='get_robot_by_rp - ERROR - запрос робота по складу, на котором более 1-го робота';
          log(rpid_, errmm__);
          raise_application_error (-20012, errmm__, TRUE);
    else
      for rr in (select * from robot where repository_part_id=rpid_) loop
        return rr.id;
      end loop;
    end if;
  end loop;
end;

-- интеллектуальная функция определения - заблокирован ли трек? (учитывает шлейф робота)
function is_track_locked(robot_id_ in number, npp_d number, dir number, maybe_locked_ number default 0, check_ask_1_robot number default 0) return number is
  cnpp number;
  ll number;
  dnppsorb number;
  is_dest_npp_reached boolean;
begin
  is_dest_npp_reached:=false;
  for r in (select * from robot where id=robot_id_) loop
    Log(r.repository_part_id,' is_track_locked robot_id_='||robot_id_||' npp_d='||npp_d||' dir='||dir);
    for rp in (select repository_type, id, max_npp, spacing_of_robots sorb, num_of_robots
               from repository_part rp where id=r.repository_part_id) loop
      if check_ask_1_robot=0 and rp.num_of_robots=1 then -- один робот - всегда все свободно
        return 1;
      end if;
      cnpp:=r.current_track_npp;
      dbms_output.put_line('  cnpp='||cnpp);
      select locked_by_robot_id into ll from track where repository_part_id=rp.id and npp=cnpp;
      if cnpp=npp_d and ll=robot_id_ /*or maybe_locked_=1 and ll=0)*/ then
         return 1; -- там же и стоим
      end if;
      -- считаем максимум сколько нужно хапануть
      dnppsorb:=add_track_npp(rp.id, npp_d,rp.sorb, dir);
      if is_track_npp_BAN_MOVE_TO(rp.id, npp_d)=1 then
        dnppsorb:=add_track_npp(rp.id, dnppsorb,1, dir);
      end if;
      loop
        if cnpp=npp_d then
          is_dest_npp_reached:=true;
        end if;
        exit when cnpp=dnppsorb and is_dest_npp_reached;
        if dir=1 then -- по часовой
           if rp.repository_type =1 then -- для кольцевого склада
             if cnpp=rp.max_npp then
                cnpp:=0;
             else
                cnpp:=cnpp+1;
             end if;
           else  -- для линейного
             if cnpp<rp.max_npp then
                cnpp:=cnpp+1;
             else
                exit; -- выход из цикла
             end if;
           end if;
        else -- против
           if rp.repository_type =1 then -- для кольцевого склада
             if cnpp=0 then
                cnpp:=rp.max_npp;
             else
                cnpp:=cnpp-1;
             end if;
           else  -- для линейного
             if cnpp>0 then
                cnpp:=cnpp-1;
             else
                exit; -- выход из цикла
             end if;
           end if;
        end if;
        select locked_by_robot_id into ll from track where repository_part_id=rp.id and npp=cnpp;
        if ll<>r.id and maybe_locked_=0 then -- ошибка
          return 0; -- путь не готов - ОШИБКА!!!
        elsif ll not in (r.id,0) and maybe_locked_=1 then
          return 0; -- путь не готов - ОШИБКА!!!
        end if;
      end loop;
    end loop;
  end loop;
  return 1; -- все проверено, мин нет
end;

-- меняет статус работа/пауза указанного огурца
procedure Change_Work_Status(rpid_ number) is
begin
  update repository_part set is_work=decode(is_work,0,1,0)
  where id=rpid_;
  commit;
end;

-- плохая блокировка робота?
function is_robot_lock_bad(rid_ number) return number is
  cnpp__ number;
  cnt1 number;
  cnt2 number;
begin
  select count(*) into cnt1 from track where locked_by_robot_id=rid_;
  if cnt1=0 then -- ничего не заблокировано, неправильно!
    return 1;
  end if;
  for rr in (select r.*, max_npp, SPACING_OF_ROBOTS sor
             from robot r, repository_part rp where r.id=rid_ and repository_part_id=rp.id) loop
    for dir in 0..1 loop -- в оба направления
      if dir=0 then -- против часовой
         cnt1:=0;
         for tt in (select * from track where repository_part_id=rr.repository_part_id and npp<rr.current_track_npp order by npp desc) loop
           cnpp__:=tt.npp;
           if tt.locked_by_robot_id=rid_ then
             cnt1:=cnt1+1;
           else
             exit;
           end if;
         end loop;
         if cnpp__=0 then -- дошли до нуля
           for tt in (select * from track where repository_part_id=rr.repository_part_id  order by npp desc) loop
             cnpp__:=tt.npp;
             if tt.locked_by_robot_id=rid_ then
               cnt1:=cnt1+1;
             else
               exit;
             end if;
             exit when cnt1>=rr.max_npp;
           end loop;
         end if;
      else -- по часовой
         cnt2:=0;
         for tt in (select * from track where repository_part_id=rr.repository_part_id and npp>rr.current_track_npp order by npp ) loop
           cnpp__:=tt.npp;
           if tt.locked_by_robot_id=rid_ then
             cnt2:=cnt2+1;
           else
             exit;
           end if;
         end loop;
         if cnpp__=rr.max_npp then -- дошли до MAX
           for tt in (select * from track where repository_part_id=rr.repository_part_id  order by npp ) loop
             cnpp__:=tt.npp;
             if tt.locked_by_robot_id=rid_ then
               cnt2:=cnt2+1;
             else
               exit;
             end if;
             exit when cnt2>=rr.max_npp;
           end loop;
         end if;
      end if;
    end loop;
    if cnt1>rr.sor and cnt2>rr.sor then
      return 1;
    end if;
  end loop;
  return 0;
end;

-- по ID робота получить целевой № секции и направление
procedure Get_Cmd_RP_Npp_Dir(rid_ number, crp_npp__ out number , crp_dir__ out number ) is
begin
  crp_npp__:=-1;
  crp_dir__:=-1;
  for crp in (select crp.* from robot r, command_rp crp where r.id=rid_ and crp.id=command_rp_id) loop
    if nvl(crp.substate,0) in (0,1,2) then -- только начала выполняться или уже доехали
      crp_npp__:=crp.npp_src;
      crp_dir__:=crp.direction_1;
    else
      crp_npp__:=crp.npp_dest;
      crp_dir__:=crp.direction_2;
    end if;
  end loop;

end;


-- получить имя ячейки по № секции на конкретном огурце (нужно для команды move)
function Get_Cell_Name_By_Track_Npp(track_npp_ in number, rp_ number) return varchar2 is
  res__ varchar2(100);
begin
  select cell_sname into res__
  from track
  where
    npp=track_npp_ and repository_part_id=rp_;
  return res__;
end;

-- получить по ID направления кусок команды в текстовом виде для отдачи роботу
function Get_Cmd_Dir_Text(dir_ in number) return varchar2 is
begin
  if dir_=1 then
    return '';
  else
    return 'CCW';
  end if;
end;

-- вычисляет расстояние между двумя треками npp по оптимальному направлению
function Calc_Min_Distance(rp_type number, max_npp number, n1 number, n2 number) return number is
  res number;
  nn1 number;
  nn2 number;
begin
  if n2<n1 then
    nn1:=n2;
    nn2:=n1;
  else
    nn1:=n1;
    nn2:=n2;
  end if;
  res:=nn2-nn1;
  if rp_type=1 then -- только для кольцевого
    if max_npp-nn2+nn1<res then
      res:=max_npp-nn2+nn1;
    end if;
  end if;
  return res;
end;

-- вычисляет расстояние между двумя ячейками по оптимальному направлению
function Calc_Min_Distance(rp_id_ number, cell1_ varchar2, cell2_ varchar2) return number is
  npp1 number;
  npp2 number;
begin
  for rr in (select repository_type rt, max_npp from repository_part where id=rp_id_) loop
    select track_npp into npp1 from cell where sname=cell1_ and repository_part_id=rp_id_;
    select track_npp into npp2 from cell where sname=cell2_ and repository_part_id=rp_id_;
    return Calc_Min_Distance(rr.rt, rr.max_npp, npp1, npp2);
  end loop;
  return -1;
end;


-- вычисляет расстояние между двумя треками npp по указанному направлению
function Calc_Distance_By_Dir(rpid_ number, n1 number, n2 number, dir_ number) return number is
  res number;
  nn number;

begin
  if n1=n2 then
     return 0;
  end if;
  for rp in (select repository_type, max_npp from repository_part where id=rpid_ ) loop
    if rp.repository_type=0 then -- линейный
      if n2<n1 and dir_=1
         or n2>n1 and dir_=0
         then
        res:= rp.max_npp*100;
      else
        res:=(abs(n2-n1));
      end if;
    else -- кольцевой
      nn:=n1;
      res:=0;
      loop
        res:=res+1;
        if dir_=1 then -- по часовой
          if nn=rp.max_npp then
            nn:=0;
          else
            nn:=nn+1;
          end if;
        else -- против
          if nn=0 then
            nn:=rp.max_npp;
          else
            nn:=nn-1;
          end if;
        end if;
        exit when nn=n2;
      end loop;
    end if;
  end loop;
  return res;
end;

-- сколько роботов на огурце находится в режиме починки?
function Calc_Repair_robots(rpid_ number) return number is
  cnt_ number;
begin
  select count(*) into cnt_ from robot where repository_part_id=rpid_ and state=obj_robot.ROBOT_STATE_REPAIR;
  return cnt_;
end;

-- взять следующий № трека по направлению (и высчитать, не пришди ли уже куда надо)
procedure get_next_npp(rp_type number, max_npp in number, cur_npp in number, npp_to in number, dir in number, next_npp out number, is_loop_end out number) is
begin
  is_loop_end:=0;
  if cur_npp=npp_to then
    is_loop_end:=1;
  end if;
  if dir=1 then -- по часовой
    if cur_npp<max_npp then
       next_npp:= cur_npp+1;
    elsif cur_npp=max_npp then
       if rp_type=0 then -- линейный
         next_npp:= cur_npp;
         is_loop_end:=1;
       else
         next_npp:=0;
       end if;
    else
       --if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
       null;
    end if;
  else
    if cur_npp>0 then
       next_npp:= cur_npp-1;
    elsif cur_npp=0 then
       if rp_type=0 then
         next_npp:= cur_npp;
         is_loop_end:=1;
       else
         next_npp:=max_npp;
       end if;
    else
       --if emu_log_level>=1 then emu_log('  gnp: Error cur_npp='||cur_npp); end if;
       null;
    end if;
  end if;
end;


-- взять ID ячейки по ее имени на конкретном огурце
function Get_Cell_ID_By_Name(rp_id_ in number, sname_ in varchar2) return number is
  res number;
begin
  select id into res
  from cell
  where sname=sname_
        and shelving_id in
            (select id from shelving where track_id in
              (select id from track where repository_part_id=rp_id_));
  return res;
end;

-- изменить направление движения команды перемещения контейнера на огурце
procedure change_cmd_rp_dir(crp_id_ number, robot_id_ number, part_ number) is
begin
  delete from track_order where robot_id=robot_id_;
  if part_=1 then
    update command_rp set direction_1=Get_Another_Direction(direction_1) where id=crp_id_;
  elsif part_=2 then
    update command_rp set direction_2=Get_Another_Direction(direction_2) where id=crp_id_;
  end if;
end;


-- примитив для добавления к номеру трека столько-то секций
function add_track_npp(rp_id_ number, npp_from_ number,npp_num_ number, dir_ number) return number is
  k_ number;
  inc_ number;
begin
  for rp in (select num_of_robots, spacing_of_robots, repository_type, max_npp
             from repository_part where id=rp_id_) loop
    k_:=npp_from_;
    inc_:=npp_num_;
    loop
      if dir_=1 then -- по часовой стрелке
        if k_=rp.max_npp then -- достигли максимума
          if rp.repository_type=0 then -- склад линейный
            return rp.max_npp;
          else -- склад кольцевой, начинаем сначала
            k_:=0;
            inc_:=inc_-1;
          end if;
        else
            k_:=k_+1;
            inc_:=inc_-1;
        end if;
      else -- против часовой стрелке
        if k_=0 then -- достигли минимума
          if rp.repository_type=0 then -- склад линейный
            return 0;
          else -- склад кольцевой, начинаем сконца
            k_:=rp.max_npp;
            inc_:=inc_-1;
          end if;
        else
            k_:=k_-1;
            inc_:=inc_-1;
        end if;
      end if;
      exit when inc_=0;
    end loop;
  end loop;
  return k_;
end;

-- проверить, есть ли возвращенный номер трека в базе. Если нет, попытаться найти № трека по имени
function get_track_npp_by_npp(npp_ in number, rp_id_ in number) return number is
  res number;
begin
  select npp into res from track where npp=npp_ and repository_part_id=rp_id_;
  return res;
  exception when others then
    select npp into res from track where name=npp_ and repository_part_id=rp_id_;
    return res;
end;

-- взять ID трека по его номеру на конкретном огурце
function Get_Track_ID_By_Npp(npp_ in number, rp_id_ in number) return number is
  res number;
begin
  select id into res from track where npp=npp_ and repository_part_id=rp_id_;
  return res;
end;

-- является ли огурец простым с одним роботом?
function Is_RP_Simple_1_Robot(rp_id_ number) return number is
begin
  for rp in (select id from repository_part where id=rp_id_ and num_of_robots=1) loop
    return 1;
  end loop;
  return 0;
end;

-- есть ли неошибочные ячейки указанного подтипа на складе?
function is_exists_cell_type(rp_id_ number, ct_ number) return number is
begin
  for cc in (select * from cell where repository_part_id=rp_id_ and hi_level_type =ct_ and is_error=0) loop
    return 1;
  end loop;
  return 0;
end;

-- находится ли трек в шлейфе поломанного робота?
function Is_Track_Near_Repair_Robot(rp_id_ number, npp_ number) return number is
  d1 number;
  d2 number;
  md number;
begin
  for rr in (select * from robot where state=obj_robot.ROBOT_STATE_REPAIR and repository_part_id=rp_id_) loop
    d1:=Calc_Distance_By_Dir(rp_id_ , npp_, rr.current_track_npp, 0);
    d2:=Calc_Distance_By_Dir(rp_id_ , npp_, rr.current_track_npp, 1);
    md:=Get_RP_Spacing_Of_robots(rp_id_)*(Get_RP_Num_Of_robots(rp_id_)-1)*2+(Get_RP_Num_Of_robots(rp_id_)-1);
    if d1<=md or d2<=md then
      return 1;
    end if;
  end loop;
  return 0;
end;



-- **********************************************************************
-- ** Собственно говоря управление

-- выполняет часть команды перемещения контейнера между ячейками
procedure Run_Cmd_RP_Parts_Prim(robot_id_ in number, crp_id_ in number, IsIgnoreBufTrackOrder boolean)  is
 new_ss number;
 ttl__ number;
 ttl_nb__ number;
 cell_sname__ varchar2(100);
 errm__ varchar2(4000);
 br_id_ number;
begin
  for robot in (select r.*, small_delta
                from robot r, repository_part rp
                where r.id=robot_id_ and r.repository_part_id=rp.id) loop
    log(robot.repository_part_id,'Начало run_transfer_part '||crp_id_||' робота '||robot_id_);
    for crp in (select * from command_rp where id=crp_id_) loop
      update robot set command_rp_id=crp_id_ where id=robot_id_ and nvl(command_rp_id,0)<>crp_id_;
      if SQL%ROWCOUNT>0 then
         obj_robot.log(robot_id_,'У робота назначили command_rp '||crp_id_);
      end if;

      if nvl(crp.substate,0) in (0,1,2) then -- только начала выполняться или уже доехали
          ttl__:=Try_Track_Lock(robot_id_, crp.npp_src, crp.direction_1, IsIgnoreBufTrackOrder, br_id_);
          if ttl__=crp.npp_src then
            log(robot.repository_part_id,'  удалось заблокировать до цели, шлем CMD_LOAD ');
            obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  4, crp.direction_1,  crp.cell_src_sname, '',
                          obj_robot.CMD_LOAD||' '||crp.cell_src_sname||';'||get_cmd_dir_text(crp.direction_1),crp.container_id);
          elsif ttl__<0 then
            log(robot.repository_part_id,'  не можем сдвинуться с места, ждем');
            if obj_robot.Get_Robot_state(br_id_)=obj_robot.ROBOT_STATE_REPAIR then -- не ремонт ли мешает?
              errm__:='  мешает ремонтный робот '||br_id_||', меняем направление LOAD';
              log(robot.repository_part_id,errm__);
              obj_ask.global_error_log(obj_ask.error_type_robot_rp,robot.repository_part_id,robot.id,errm__);
              change_cmd_rp_dir(robot.command_rp_id,robot.id,1);
            end if;
          elsif ttl__<>robot.current_track_npp
                and Calc_Distance_By_Dir(robot.repository_part_id, robot.current_track_npp, ttl__, crp.direction_1) >robot.small_delta
            then -- можем сдвинуться
            log(robot.repository_part_id,'  не удалось заблокировать до цели, шлем MOVE до '||ttl__);
            ttl_nb__:=Get_Track_Npp_Not_Baned(robot.repository_part_id, ttl__, crp.direction_1);
            if ttl_nb__<>robot.current_track_npp then
              log(robot.repository_part_id,'  ttl_nb__='||ttl_nb__);
              if robot.is_use_checkpoint=1 then -- использовать промежуточные точки
                obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  4, crp.direction_1,  crp.cell_src_sname, Null,
                              obj_robot.CMD_LOAD||' '||crp.cell_src_sname||' cp='||ttl_nb__||';'||get_cmd_dir_text(crp.direction_1),crp.container_id,ttl_nb__);
              else -- не использовать промежуточные точки
                cell_sname__:=Get_Cell_Name_By_Track_Npp(ttl_nb__,robot.repository_part_id);
                obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  6, crp.direction_1,  Null, cell_sname__,
                              obj_robot.CMD_MOVE||' '||cell_sname__||';'||get_cmd_dir_text(crp.direction_1),crp.container_id);
              end if;
            else
              log(robot.repository_part_id,'  не можем послать, т.к. трек запрещен к MOVE и он один');
            end if;
          end if;
          update command_rp set substate=1 where id=crp_id_ and nvl(substate,0)<1;
          if SQL%ROWCOUNT>0 then
             log(robot.repository_part_id,'У команды '||crp_id_||' назначили новое подостояние 1');
          end if;
      elsif crp.substate in (3,4) then -- все еще едем куда надо
          ttl__:=Try_Track_Lock(robot_id_, crp.npp_dest, crp.direction_2, IsIgnoreBufTrackOrder, br_id_);
          if ttl__=crp.npp_dest then
            log(robot.repository_part_id,'  удалось заблокировать до цели, шлем CMD_UNLOAD ');
            obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  5, crp.direction_2,  '', crp.cell_dest_sname,
                         obj_robot.CMD_UNLOAD||' '||crp.cell_dest_sname||';'||get_cmd_dir_text(crp.direction_2),crp.container_id);
          elsif ttl__<0 then
            log(robot.repository_part_id,'  не можем сдвинуться с места, ждем');
            if obj_robot.Get_Robot_state(br_id_)=obj_robot.ROBOT_STATE_REPAIR then -- не ремонт ли мешает?
              errm__:='  мешает ремонтный робот '||br_id_||', меняем направление UNLOAD ';
              obj_ask.global_error_log(obj_ask.error_type_robot_rp,robot.repository_part_id,robot.id,errm__);
              log(robot.repository_part_id,errm__);
              change_cmd_rp_dir(robot.command_rp_id,robot.id,2);
            end if;
          elsif ttl__<>robot.current_track_npp
                and Calc_Distance_By_Dir(robot.repository_part_id, robot.current_track_npp, ttl__, crp.direction_2) >robot.small_delta
            then -- можем сдвинуться
            log(robot.repository_part_id,'  не удалось заблокировать до цели, шлем MOVE до '||ttl__);
            ttl_nb__:=Get_Track_Npp_Not_Baned(robot.repository_part_id, ttl__, crp.direction_2);
            if ttl_nb__<>robot.current_track_npp then
              log(robot.repository_part_id,'  ttl_nb__='||ttl_nb__);
              if robot.is_use_checkpoint=1 then -- использовать промежуточные точки
                obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  5, crp.direction_2,  Null, crp.cell_dest_sname,
                              obj_robot.CMD_UNLOAD||' '||crp.cell_dest_sname||' cp='||ttl_nb__||';'||get_cmd_dir_text(crp.direction_2),crp.container_id,ttl_nb__);
              else -- не использовать промежуточные точки
                cell_sname__:=Get_Cell_Name_By_Track_Npp(ttl_nb__,robot.repository_part_id);
                obj_robot.set_command_inner(robot_id_,  crp_id_, 1,  6, crp.direction_2,  Null, cell_sname__,
                              obj_robot.CMD_MOVE||' '||cell_sname__||';'||get_cmd_dir_text(crp.direction_2),crp.container_id);
              end if;
            else
              log(robot.repository_part_id,'  не можем послать, т.к. трек запрещен к MOVE и он один');
            end if;
          end if;
      else
        log(robot.repository_part_id,'ERROR - crp.substate='||crp.substate||', а в Run_Transfer_Part все равно пришли!');
      end if;
    end loop;
  end loop;


end;

-- эмулирует проставление параметров для command_rp в случае, когда на подскладе 1 робот
procedure Optimizer_Emu_1_robot(crp_id_ number) is
  dirl1__ number;
  dirl2__ number;
  dist0__ number;
  dist1__ number;
  fd__ number;
begin
  for ri in (select rp.repository_type , r.current_track_npp, crp.npp_dest, crp.npp_src, r.id robot_id, rp.id rp_id_
          from command_rp crp, repository_part rp , robot r
          where crp.id=crp_id_ and crp.rp_id=rp.id and r.repository_part_id=rp.id) loop
    fd__:=service.get_rp_param_number('force_dir',-1);
    if fd__>=0 then
          dirl1__:=fd__;
          dirl2__:=fd__;
    else
      if ri.repository_type=0 then -- линейный
        if ri.current_track_npp>ri.npp_src then
          dirl1__:=0;
        else
          dirl1__:=1;
        end if;
        if ri.npp_dest>ri.npp_src then
          dirl2__:=1;
        else
          dirl2__:=0;
        end if;
      else -- кольцевой
        dist0__:=Calc_Distance_By_Dir(ri.rp_id_ , ri.current_track_npp, ri.npp_src, 0);
        dist1__:=Calc_Distance_By_Dir(ri.rp_id_ , ri.current_track_npp, ri.npp_src, 1);
        if dist0__<dist1__ then
          dirl1__:=0;
        else
          dirl1__:=1;
        end if;
        dist0__:=Calc_Distance_By_Dir(ri.rp_id_ , ri.npp_src, ri.npp_dest, 0);
        dist1__:=Calc_Distance_By_Dir(ri.rp_id_ , ri.npp_src, ri.npp_dest, 1);
        if dist0__<dist1__ then
          dirl2__:=0;
        else
          dirl2__:=1;
        end if;
      end if;
    end if;
    update command_rp
    set  direction_1=dirl1__, direction_2=dirl2__, robot_id=ri.robot_id
    where id=crp_id_;
  end loop;
end;

-- назначаем новые comand_rp
procedure Set_New_Cmd_RPs(rpid_ number) is
  cnt__ number;
  cirecord__ command_inner%ROWTYPE;
  crprecord__ command_rp%ROWTYPE;
  robot_to_crp__ number;
begin
  -- еще нет команды, назначаем
  for cmrp in (select /*+RULE*/ cr.*
               from command_rp cr, cell c, cell_type ct, robot r
               where cr.rp_id=rpid_ and cr.state=1
                     and command_type_id in (3)
                     and cr.cell_src_id =c.id and c.hi_level_type=ct.id
                     and (r.id=cr.robot_id or is_rp_simple_1_robot(rpid_)=1)
                     and obj_robot.Is_Robot_Ready_For_Cmd(r.id)=1
                     and r.repository_part_id=rpid_
               order by PRIORITY desc, priority_inner, ct.obligotary_to_free desc, abs(r.current_track_npp-cr.npp_src),cr.id) loop
     Log(rpid_,'Set_New_Cmd_RPs - есть command_rp - кандидат на назначение '||cmrp.id);
     if nvl(cmrp.robot_id,0)>0 then
       robot_to_crp__:=cmrp.robot_id;
     else -- для подсклада с одним роботом
       robot_to_crp__:=get_robot_by_rp(rpid_);
     end if;
     if obj_robot.Is_Robot_Ready_For_Cmd(robot_to_crp__)=1 then -- могло и поменяться
        select count(*) into cnt__ from command_inner  where robot_id=cmrp.robot_id and state=3;
        Log(rpid_,'  активных по роботу команд CI=!'||cnt__);
        if cnt__<>0 then -- ошибка, робот свободен, а задачи невыполнены
          select * into cirecord__ from command_inner where robot_id=cmrp.robot_id and state=3 and rownum=1;
          Log(rpid_,'ERROR - На подскладе есть работающие команды ci.id='||cirecord__.id||'. Выходим из такта!');
          CONTINUE;
        end if;
        select count(*) into cnt__ from command_rp  where robot_id=cmrp.robot_id and state=3;
        Log(rpid_,'  активных по роботу команд RP=!'||cnt__);
        if cnt__<>0 then -- ошибка, хотим назначить command_rp, а есть еще невыполненные
          select * into crprecord__ from command_rp where robot_id=cmrp.robot_id and state=3 and rownum=1;
          Log(rpid_,'ERROR - На подскладе есть работающие команды cmrp.id='||crprecord__.id||'. Выходим из такта!');
          CONTINUE;
        end if;
        log(rpid_,'Найдена команда для назначения '||cmrp.id||' для робота '||cmrp.robot_id);
        if cmrp.command_type_id in (3) then -- перемещение простое контейнера
          log(rpid_,'Это команда простого перемещения контейнера ');
          if is_rp_simple_1_robot(rpid_)=1 then -- простой АСК с одним роботом
            Optimizer_Emu_1_robot(cmrp.id);
          end if;
          update command_rp
          set
            state=3, date_time_begin=sysdate, substate=1
          where id=cmrp.id;
          log(rpid_,'Проставили направления, робота, состояние, дату, подсостояние');
          for rr in (select * from command_rp where id=cmrp.id ) loop
            update robot set command_rp_id=cmrp.id where id=rr.robot_id;
            --Run_Cmd_RP_Parts_Prim(rr.robot_id, cmrp.id);
          end loop;
        end if; -- если команда та что надо
     end if;
  end loop;  -- для cmrp
end;

-- формируем доделки comand_rp или прогоняем робота мешающего по заявке
procedure Run_Cmd_Parts(rid_ number) is
  AwayPar__ number;
  S_MUST_REAL_CMD boolean;
begin
  S_MUST_REAL_CMD:=false;
  for rrp in (select * from robot where id=rid_) loop
    -- если  остались свободные роботы, то пытаемся дозавершить команды
    for toi in (select *
                 from track_order tor
                 where rid_=robot_stop_id
                       --and obj_robot.Is_Robot_Ready_For_Cmd_Inner(r.id)=1
                 ) loop

          log(rrp.repository_part_id,'На робота '||rid_||' уже есть заявка '||toi.id||', прогоняем ');
          AwayPar__:=Robot_Stop_Drive_Away_Try(rid_, toi.id);
          if (AwayPar__ = 3) then -- есть команда которую можно присунуть не мешая отгону
             S_MUST_REAL_CMD:=true;
          else
             return; -- во всех остальных случаях вываливаемся
          end if;
     end loop;

     -- отмены всякие если нужно
     for rr in (select * from robot where id=rid_) loop
       if (nvl(rr.command_rp_id,0)=0 ) or nvl(rr.command_inner_assigned_id,0)<>0 then
          log(rr.repository_part_id,'нет назначенной команды CRP, или делаются какие-то CMD_INNER');
          return;
       end if;
     end loop;

    for crp in (select * from command_rp where id=rrp.command_rp_id)  loop
        if crp.command_type_id in (3,7) then
          -- перемещение простое контейнера
          if crp.substate in (0,1,2,3,4)  then
            Run_Cmd_RP_Parts_Prim(crp.robot_id, crp.id, S_MUST_REAL_CMD);
          else
            -- че сюда дошли, странно
            log(rrp.repository_part_id,'ERROR - такого подстатуса команды быть не должно - не то поставил ручками?');
          end if;
        end if;
      end loop;
  end loop;


end;

-- есть ли активные команды перемещения контейнеров на огурце?
function Is_Active_Command_RP(rpid_ number) return number is
begin
  for crp in (select * from command_rp where rp_id=rpid_ and state not in (2,5)) loop
    return 1;
  end loop;
  return 0;
end;

-- перемещаем робота прочь, если в настройках АСК указано премещать робота после unload
procedure Move_Robot_Away_If_Ness(rpid_ number) is
  npp_new__ number;
  --npp_lock_to__ number;
  cmd_cell__ varchar2(100);
  dir__ number;
  ttl__ number;
  br_id_ number;
begin
  for rr in (select r.*, rp.spacing_of_robots sorb
             from robot r, repository_part rp
             where rp.id=rpid_ and repository_part_id=rp.id
                   and obj_robot.Is_Robot_Ready_For_Cmd(r.id)=1
                   and Is_Active_Command_RP(rp.id)=0) loop -- робот свободен и на него не закреплена команда общая
    for ci in (select * from command_inner where robot_id=rr.id and date_time_create>sysdate-3 order by id desc) loop -- ищем последнюю команду на этого робота
      if ci.command_type_id=5 then -- UNLOAD
        for cc in (select * from cell where ci.cell_dest_id=cell.id and nvl(move_after_cmd_on_npp,0)>0) loop
          Log(rpid_,'Move_Robot_Away_If_Ness - нужно двигать робота '||rr.id||' чтоб не мешал отборщику после UNLOAD');
          npp_new__:=cc.track_npp+cc.move_after_cmd_on_npp;
          cmd_cell__:=Get_Cell_Name_By_Track_Npp(npp_new__,rpid_);
          if cc.move_after_cmd_on_npp>0 then
            dir__:=1;
          else
            dir__:=0;
          end if;
          --npp_lock_to__:=add_track_npp(rpid_, npp_new__,rr.sorb, dir__);
          Log(rpid_,'  пытаемся заблокировать до секции '||npp_new__||' роботом '||rr.id);
          ttl__:=Try_Track_Lock(rr.id, npp_new__, dir__, false, br_id_);
          obj_robot.set_command_inner(rr.id,  0, 1,  6, dir__,  Null, cmd_cell__,
                          obj_robot.CMD_MOVE||' '||cmd_cell__||';'||get_cmd_dir_text(dir__),0);

        end loop;
      end if;
      exit;
    end loop;
  end loop;
end;

-- дать команду InitY, если нужно
procedure InitY_If_Ness(rpid_ number) is
begin
  for rr in (select * from robot where repository_part_id=rpid_ and is_present=1) loop
    obj_robot.InitY_If_Ness(rr.id );
  end loop;
end;

-- сменить направление команды перемещения контейнера для конкретного робота
procedure Robot_Cmd_RP_Change_Dir(rid_ number) is
begin
  for rr in (select * from robot where id=rid_) loop
    if nvl(rr.command_rp_id,0)<>0 then
      for crp in (select * from command_rp where id=rr.command_rp_id) loop
        if nvl(crp.substate,0) in (0,1,2) then
           update command_rp set direction_1 = Get_Another_Direction(direction_1) where id=crp.id;
        elsif nvl(crp.substate,0) in (3,4) then
           update command_rp set direction_2 = Get_Another_Direction(direction_2) where id=crp.id;
        else
          obj_robot.Log(rid_,'ERROR - пришла смена направления, а substate команды '||crp.substate);
        end if;
        return;
      end loop;
      obj_robot.Log(rid_,'ERROR - пришла смена направления, а команда не найдена');
      return;
    end if;
    obj_robot.Log(rid_,'ERROR - пришла смена направления, а команда за роботом незакреплена ');
    return;
  end loop;
  obj_robot.Log(rid_,'ERROR - пришла смена направления, а робот '||rid_||' не найден!');
end;

-- заявка на блокировку трека
function Track_Order_Lock(rid_ number, to_id_ number,
                          npp_to_sorb__ out number , crp_npp__ out number , crp_dir__ out number ) return number is
  ttl__ number;
  br_id_ number;
begin
  for rr in (select r.*, spacing_of_robots
             from robot r, repository_part rp
             where r.id=rid_ and repository_part_id=rp.id) loop
      -- проверяем, что заявка не самая свежая
      for tor in (select * from track_order where repository_part_id=rr.repository_part_id order by id) loop
        if tor.robot_id=rid_ then
          obj_robot.Log(rid_,'  отбой прогона, самая свежая заявка от этого робота');
          return -1;
        end if;
        exit;
      end loop;

      for to_ in (select * from track_order where id=to_id_) loop
        crp_npp__:=-1;
        Get_Cmd_RP_Npp_Dir(rid_, crp_npp__, crp_dir__);
        if nvl(rr.command_rp_id,0)>0 and crp_npp__>=0 then
          if crp_dir__=to_.direction and is_track_locked(rid_,crp_npp__,crp_dir__,1)=1 then
            obj_robot.Log(rid_,'  отбой прогона, можно тиснуть команду '||rr.command_rp_id||' до трека '||crp_npp__||' dir='||crp_dir__);
            return -2;
          end if;
          if is_track_locked(rid_,crp_npp__,crp_dir__,0)=1 then
            obj_robot.Log(rid_,'  отбой прогона, целевой трек и так заблокирован');
            return -2;
          end if;
        end if;

        npp_to_sorb__:=Add_Track_Npp(rr.repository_part_id, to_.Npp_To,Rr.Spacing_Of_Robots+1, to_.Direction);
        ttl__:=Try_Track_Lock(rid_, npp_to_sorb__, to_.Direction, true, br_id_);
        return ttl__;
      end loop;

  end loop;
end;

-- является ли указанная заявка на блокировку между указанными треками по заданному направлению?
function Is_Track_Part_Between(to_id_ number, npp_from number,  npp_to number,  dir number) return boolean is
begin
  for to_ in (select * from track_order where to_id_=id) loop
            -- ->->
            if ((to_.Direction = 1) and (dir = 1)) then -- заявка по часовой стеклки и часть трека по часовой стрелки
                if (to_.Npp_To < to_.Npp_From) then -- заявка с перехлестом через 0
                    if (npp_to < npp_from) then -- участок с перехлестом через 0
                        return true; -- оба перехлеста
                    else -- участок без перехлеста через 0
                        return (npp_to >= to_.Npp_From) -- участок вначале попадает
                               or (npp_from <= to_.Npp_To) -- участок вконце попадает
                               ;
                    end if;
                else -- без перехлеста через 0
                    if (npp_to < npp_from) then -- с перехлестом через 0
                        return (npp_from <= to_.Npp_To) -- участок сначала задевает заявку
                               or (npp_to >= to_.Npp_From) -- участок в конце задевает заявку
                               ;
                    else -- без перехлеста через 0
                        return (npp_to >= to_.Npp_From and npp_from <= to_.Npp_From) -- участок вначале попадает
                               or (npp_from >= to_.Npp_From and npp_to <= to_.Npp_To) -- участок целиком попадает
                               or (npp_from <= to_.Npp_To and npp_to >= to_.Npp_To) -- участок справа попадает
                               ;
                    end if;
                end if;
            -- <-<-
            elsif ((to_.Direction = 0) and (dir = 0)) then -- заявка против часовой стрелки и часть трека против часовой стрелки
                if (to_.Npp_To < to_.Npp_From) then -- заявка без перехлеста через 0
                    if (npp_to < npp_from) then -- участок без перехлеста через 0
                        return (npp_from >= to_.Npp_To and npp_to <= to_.Npp_To) -- участок слева попадает
                               or (npp_from <= to_.Npp_From and npp_to >= to_.Npp_To) -- участок целиком попадает
                               or (npp_from >= to_.Npp_From and npp_to <= to_.Npp_From) -- участок справа попадает
                               ;
                    else -- с перехлестом участок через 0
                        return (npp_from >= to_.Npp_To) -- участок сначала задевает заявку
                               or (npp_to <= to_.Npp_From) -- участок в конце задевает заявку
                               ;
                    end if;
                else -- заявка с перехлестом через 0
                    if (npp_to < npp_from) then -- участок без перехлеста через 0
                        return (npp_to <= to_.Npp_From) -- участок вначале попадает
                               or (npp_from >= to_.Npp_To); -- участок вконце попадает
                    else -- с перехлестом участок через 0
                        return true;
                    end if;
                end if;
            -- -><-
            elsif ((to_.Direction = 1) and (dir = 0)) then -- заявка по часовой стрелки , а часть трека против часовой стрелки
                if (to_.Npp_To < to_.Npp_From) then -- заявка с перехлестом через 0
                    if (npp_to < npp_from) then -- участок без перехлеста через 0
                        return (npp_from >= to_.Npp_From) -- участок слева попадает
                               or (npp_to <= to_.Npp_To) -- участок справа попадает
                               ;
                    else -- участок с перехлестом через 0
                      return true;
                    end if;
                else -- заявка без перехлеста через 0
                    if (npp_to < npp_from) then -- участок без перехлеста через 0
                        return (npp_from >= to_.Npp_From and npp_to <= to_.Npp_To) -- участок попадает
                               ;
                    else -- участок с перехлестом через 0
                        return (npp_from >= to_.Npp_From) -- участок слева попадает
                               or (npp_to <= to_.Npp_To) -- участок справа попадает
                               ;
                    end if;
                end if;
            -- <-->
            elsif ((to_.Direction = 0) and (dir = 1)) then -- заявка против часовой стрелки , а часть трека по часовой стрелки
                if (to_.Npp_To < to_.Npp_From) then -- заявка без перехлеста через 0
                    if (npp_to < npp_from) then -- участок c перехлестом через 0
                        return (npp_to >= to_.Npp_To) -- участок слева попадает
                               or (npp_from <= to_.Npp_From) -- участок справа попадает
                               ;
                    else -- участок без перехлеста через 0
                        return (npp_from <= to_.Npp_From and npp_to >= to_.Npp_From) -- участок справа попадает
                               or (npp_from >= to_.Npp_To and npp_to <= to_.Npp_From) -- участок целиком попадает
                               or (npp_to >= to_.Npp_To and npp_from <= to_.Npp_To) -- участок справа попадает
                               ;
                    end if;
                else -- заявка c перехлестом через 0
                    if (npp_to < npp_from) then -- участок c перехлестом через 0
                        return true;
                    else -- участок без перехлеста через 0
                        return (npp_from <= to_.Npp_From) -- участок слева попадает
                               or (npp_to >= to_.Npp_To) -- участок справа попадает
                               ;
                    end if;
                end if;
            end if;
  end loop;
  return false; -- сюда дойти не должно вроде как
end;

-- заблокировано ли крайние треки в шлейфе робота?
function Robot_Track_Lock_Only_Around(rid_ number) return boolean is
  sr__ number;
  l__ number;
  r__ number;
  lrb__ number;
  rrb__ number;
begin
  for rr in (select r.repository_part_id , rp.spacing_of_robots, current_track_npp
             from robot r, repository_part rp
             where r.id=rid_ and repository_part_id=rp.id) loop
    sr__:=rr.spacing_of_robots+1;
    l__:= Add_Track_Npp(rr.repository_part_id, rr.current_track_npp, sr__, 0);
    r__:= Add_Track_Npp(rr.repository_part_id, rr.current_track_npp, sr__, 1);
    select locked_by_robot_id into lrb__ from track where repository_part_id=rr.repository_part_id and npp=l__;
    select locked_by_robot_id into rrb__ from track where repository_part_id=rr.repository_part_id and npp=r__;
    return (lrb__<>rid_ and rrb__<>rid_);
  end loop;
end;

-- получить ближайший трек по заданному направлению, в который можно делать move
function Get_Track_Npp_Not_Baned(rp_id_ number, npp_ number, dir_ number) return number is
  new_npp__ number;
begin
  for tt in (select * from track where npp=npp_ and repository_part_id =rp_id_ and ban_move_to =1) loop
    -- нельзя сюда ехать
    new_npp__:=add_track_npp(rp_id_ , npp_ ,1, Get_Another_Direction(dir_));
    return  new_npp__;
  end loop;
  return npp_; -- сюда можно ехать
end;

-- пытаемся прогнать робота, который мешает двинуться
function Robot_Stop_Drive_Away_Try(rid_ number, tor_id_ number) return number is
            -- =0, не можем двинуться
            -- =1, прогнали явно
            -- =3, есть по направлению команда (или по смененнному), отбой прогона, и так уйдем
            -- =4, надо ждать цепочки событий с заявок

  npp_to_sorb__ number;
  ttl__ number;
  ttl_nb__ number;
  m_cell_sname__ varchar2(200);
  crp_npp__ number;
  crp_dir__ number;
begin
  if obj_robot.Is_Robot_Ready_For_Cmd_Inner(rid_)=1 then
    for rr in (select r.repository_part_id,  spacing_of_robots, r.current_track_npp, current_track_id
               from robot r, repository_part rp
               where r.id=rid_ and repository_part_id=rp.id )loop
      obj_robot.Log(rid_,'Робот готов для команд новых, прогоняем его нафиг');
      for to__ in (select * from track_order where id=tor_id_) loop
        ttl__:=Track_Order_Lock(rid_, to__.id, npp_to_sorb__, crp_npp__, crp_dir__);
        if (ttl__ >= 0) then -- можно двинуться хоть чутка
          -- анализируем, может нужно менять направление команды?
          if is_track_locked(rid_,crp_npp__,Get_another_Direction(crp_dir__),0)=1 then
            obj_robot.Log(rid_,'  отбой прогона, меняем направление команды');
            Robot_Cmd_RP_Change_Dir(rid_);
            return 3;
          end if;
          ttl_nb__ :=Get_Track_Npp_Not_Baned(rr.repository_part_id, ttl__, Get_another_Direction(to__.direction)); -- crp_dir__
          if ttl_nb__<>rr.current_track_npp then
            obj_robot.Log(rid_,'  ttl__='||ttl__||' ttl_nb__='||ttl_nb__);
            m_cell_sname__:=Get_Cell_Name_By_Track_Npp(ttl_nb__, rr.repository_part_id);
            if is_track_locked(rid_, ttl_nb__, to__.direction)=1 then
              obj_robot.Set_Command_Inner(rid_, 0, 1, 6, to__.direction,
                            Get_Cell_Name_By_Track_ID(rr.current_track_id),
                            m_cell_sname__,
                            'MOVE '||m_cell_sname__||';'||get_cmd_dir_text(to__.direction));
              return 1;
            else
              obj_robot.Log(rid_,'  движение к забаненной точке невозможно! Ждем освобождения! ');
              return 0;
            end if;
          else
            obj_robot.Log(rid_,'  не можем двинуться - трек среди запрещенных к MOVE и он один');
            return 0;
          end if;

        else -- проблема при блокировке по треку
          if (ttl__ = -1) then -- тупо не можем сдвинуться
            for toa__ in (select * from track_order
                          where repository_part_id=rr.repository_part_id and robot_id<>rid_ and robot_stop_id<>rid_) loop

              if (Is_Track_Part_Between(toa__.id,Add_Track_Npp(rr.repository_part_id, rr.current_track_npp, rr.spacing_of_robots, 0),
                                      Add_Track_Npp(rr.repository_part_id, rr.current_track_npp, rr.spacing_of_robots, 1),
                                      1) and
                  (Robot_Track_Lock_Only_Around(rid_)) -- что типа тупо стоим ждем
                  ) then
                  return 4; -- нужно ждать
              end if;
            end loop;
            return 0; -- нужно двигаться, но не можем
          else -- и не надо двигаться
            return 3; -- и не нужно двигаться, есть тут еще дела
          end if;
        end if;
      end loop;

      /*
      -- проверяем, а нет ли более свежей заявки
      for tor in (select * from track_order where repository_part_id=rr.repository_part_id order by id) loop
        if tor.robot_id=rid_ then
          obj_robot.Log(rid_,'  отбой прогона, самая свежая заявка от этого робота');
          return;
        end if;
        exit;
      end loop;

      -- проверяем, а нет ли команды "по пути"
      for crp in (select crp.* from robot r, command_rp crp where r.id=rid_ and crp.id=command_rp_id) loop
        if nvl(crp.substate,0) in (0,1,2) then -- только начала выполняться или уже доехали
          crp_npp__:=crp.npp_src;
          crp_dir__:=crp.direction_1;
        else
          crp_npp__:=crp.npp_dest;
          crp_dir__:=crp.direction_2;
        end if;
        if crp_dir__=dir_ and is_track_locked(rid_,crp_npp__,crp_dir__,1)=1 then
          obj_robot.Log(rid_,'  отбой прогона, можно тиснуть команду '||crp.id||' до трека '||crp_npp__||' dir='||crp_dir__);
          return;
        end if;
        if is_track_locked(rid_,crp_npp__,crp_dir__,0)=1 then
          obj_robot.Log(rid_,'  отбой прогона, целевой трек и так заблокирован');
          return;
        end if;
      end loop;

      npp_to_sorb__:=add_track_npp(rr.repository_part_id, npp_to_,rr.spacing_of_robots+1, dir_);
      ttl__:=Try_Track_Lock(rid_ , npp_to_sorb__, dir_ );



      if ttl__=npp_to_sorb__ then
        m_cell_sname__:=Get_Cell_Name_By_Track_Npp(npp_to_sorb__, rr.repository_part_id);
      elsif ttl__<>rr.current_track_npp and ttl__>=0 then
      else
        obj_robot.Log(rid_,'ERROR - Не могу прогнаться, все заблокировано');
        return;
      end if;
*/
    end loop;

  end if;
end;

-- неинтеллектуальный запрос формирования заявки на блокировку трека
function Form_Track_Order(rid_ number, npp_from_ number, npp_to_ number, dir_ number, robot_stop_id_ number) return boolean is
  cnt number;
  nor_ number;
begin
  for r in (select * from robot where id=rid_) loop
    Log(r.repository_part_id,'Пришла заявка на трек от робота '||rid_||' NPP_FROM='||NPP_FROM_||' NPP_TO='||NPP_TO_||' dir='||dir_||' robot_stop_id_='||robot_stop_id_);

    -- первым делом проверяем, а нет ли уже заявки от этого же робота
    for tt in (select * from track_order where repository_part_id=r.repository_part_id and rid_=robot_id) loop
        Log(r.repository_part_id,'ERROR - попытка заявки, когда уже есть заявка от робота '||rid_||' NPP_FROM='||tt.NPP_FROM||' NPP_TO='||tt.NPP_TO||' DIRECTION='||tt.DIRECTION||' robot_stop_id='||tt.robot_stop_id);
        return true;
    end loop;

    select count(*) into cnt from track_order where repository_part_id=r.repository_part_id;
    select num_of_robots into nor_ from repository_part where id=r.repository_part_id;
    if cnt>=nor_-1 then
      Log(r.repository_part_id,'ERROR - слишком много заявок по подскладу, отбой!');
      return false;
    end if;
    for tt in (select * from track_order where repository_part_id=r.repository_part_id) loop
      if robot_stop_id_=tt.robot_stop_id then
        Log(r.repository_part_id,'ERROR - попытка второй заявки на одного мешающего робота');
        return false;
      end if;
      if robot_stop_id_=tt.robot_id then
        Log(r.repository_part_id,'ERROR - попытка ранее инициировавшего заявку робота выставить мешающим');
        return false;
      end if;
      if (tt.direction<>dir_) and Is_Track_Part_Between(tt.id, npp_from_ ,  npp_to_ ,  dir_ ) then
        Log(r.repository_part_id,'ERROR - попытка добавить встречную мешающую заявку');
        return false;
      end if;

    end loop;
    insert into track_order(robot_id, repository_part_id,npp_from, npp_to,direction, robot_stop_id)
    values(rid_, r.repository_part_id, npp_from_, npp_to_, dir_, robot_stop_id_);
  end loop;
  return true;
end;

-- корректируем заявку на блокировку трека по вновь открвышимся обстоятельствам
function Correct_Npp_To_Track_Order(rid_ number, to_rid_ number, Dir_ number, npp_to_ number) return number is
  npp_to_ar number;
begin
  for ro_ in (select rp.num_of_robots , Spacing_Of_Robots, rp.id rpid
              from robot_order ro, robot r, repository_part rp
              where Robot_ID = rid_ and Corr_Robot_ID=to_rid_  and dir=Dir_
                    and rid_=r.id and repository_part_id=rp.id) loop
            if (ro_.num_of_robots > 0) then
                npp_to_ar:= Add_Track_Npp(ro_.rpid, npp_to_, ro_.Num_Of_Robots * (ro_.Spacing_Of_Robots * 2 + 1), Dir_);
            else
                npp_to_ar:= npp_to_;
            end if;
            return npp_to_ar ;
  end loop;
  return npp_to_ ;
end;

-- является ли трек запрещенным для команд Move туда?
function is_track_npp_BAN_MOVE_TO(rp_id_ number, npp_ number) return number is
  res_ number;
begin
  select nvl(ban_move_to,0) into res_ from track where repository_part_id=rp_id_ and npp=npp_;
  return res_;
  exception when others then
    return 0;
end;

-- функция примитивной блокировки трека
procedure TrackLockPrim(rpid_ number, rid_ number) is
begin
  update track
  set locked_by_robot_id=rid_
  where repository_part_id =rpid_ and npp in (select npp from tmp_track_lock where rp_id=rpid_);
  delete from tmp_track_lock where rp_id=rpid_;
end;

-- возврщает track_npp, до которого удалось дойти
-- если не может сдвинуться с места, шлет -1
-- если не удалось дойти, то шлет заявку на участок пути
-- здесь задаем № трека без учета ореола (интеллектуальное)
--function Try_Track_Lock(rid_ number,  npp_to_ number, dir_ number default 1,  IsIgnoreBufTrackOrder boolean default false) return number is
function Try_Track_Lock(rid_ number,  npp_to_ number, dir_ number ,  IsIgnoreBufTrackOrder boolean, barrier_robot_id out number ) return number is
  npp_from_sorb__ number;
  npp_to_sorb__ number;
  npp_cur__ number;
  npp_to_was_locked__ boolean;
  npp_old__ number;
  npp_tmp__ number;
  distance__ number;
  cnt_ number;
  npp_to_ar number;
  ft boolean;
begin
  barrier_robot_id:=0; -- типа ничего не мешает
  for rp in (select rp.id, num_of_robots, spacing_of_robots, repository_type, max_npp, r.current_track_npp
          from robot r, repository_part rp where r.id=rid_ and r.repository_part_id=rp.id ) loop
    delete from tmp_track_lock where rp_id=rp.id;
    Log(rp.id,'Try_Track_Lock robot='||rid_||' робот находится c_npp='||rp.current_track_npp||' npp_to_='||npp_to_ ||' dir_='||dir_);
    if is_track_locked(rid_ , npp_to_ , dir_ ,0,1)=1 then
      Log(rp.id,'  уже заблокировано, нет смысла блокировать');
      return npp_to_;
    end if;
    if rp.current_track_npp=npp_to_ then
      Log(rp.id,'  находится робот там же, куда нужно дойти. Бред какой-то');
      return npp_to_;
    end if;
    npp_from_sorb__:=add_track_npp(rp.id, rp.current_track_npp,rp.spacing_of_robots+1, dir_);
    npp_to_sorb__:=add_track_npp(rp.id, npp_to_,rp.spacing_of_robots,dir_);
    if is_track_npp_BAN_MOVE_TO(rp.id,npp_to_)=1 then
      Log(rp.id,'  попали на BAN_MOVE_TO, увеличиваем npp_to_sorb__ на 1 в сторону '||dir_);
      npp_to_sorb__:=add_track_npp(rp.id, npp_to_sorb__,1,dir_);
    end if;
    npp_cur__:=npp_from_sorb__;
    -- для блокировки around или на 1 секцию
    distance__:=Calc_Distance_By_Dir(rp.id, rp.current_track_npp, npp_to_, dir_);
    npp_to_was_locked__:=(npp_to_=rp.current_track_npp) or (distance__<=rp.spacing_of_robots);
    npp_old__:=-1;
    Log(rp.id,'  npp_from_sorb__='||npp_from_sorb__||' npp_to_sorb__='||npp_to_sorb__);

    -- а теперь проверяем заявки, если нужно
    if (not IsIgnoreBufTrackOrder) then
      cnt_:=0;
      for to_ in (select * from track_order where repository_part_id=rp.id order by id) loop
        exit when (cnt_= 0) and (to_.Robot_ID = rid_); -- если самая свежая заявка от текущего робота, то ему все пофиг
        if ((to_.Robot_ID <> rid_) and (to_.Robot_Stop_ID <> rid_) ) then
           npp_to_ar:= Correct_Npp_To_Track_Order(rid_, to_.Robot_ID, Dir_, npp_to_sorb__);
           if (
               (
                 Is_Track_Part_Between(rp.id,npp_from_sorb__, npp_to_ar, Dir_)
                 or Is_Track_Part_Between(rp.id,npp_from_sorb__, npp_to_, Dir_) -- это нужно чтобы избежать перехлеста при блокировки с 44 по 42 по часовой
               )
               and  Is_Track_Locked(rid_, npp_to_, Dir_, 0)=0) then
               Log(rp.id,'  отмена запроса на блокировку трека, т.к. требуемый участок уже в заявке по цепочке');
               return npp_old__;
           end if;
        end if;
        cnt_:=cnt_+1;
      end loop;
    end if;

    loop
      --Log(rp.id,'  loop npp_cur__='||npp_cur__);
      for tr in (select * from track where repository_part_id=rp.id and npp=npp_cur__) loop
        if tr.locked_by_robot_id =0 then
          --update track set locked_by_robot_id=rid_ where id=tr.id;
          insert into tmp_track_lock(npp, rp_id) values(npp_cur__,rp.id);
          -- освобождаем заявку с трека
          for tor in (select *  from track_order where robot_id=rid_ and npp_from=npp_cur__ and npp_from<>npp_to) loop
            npp_tmp__:=add_track_npp(rp.id, npp_cur__,1, get_another_direction(dir_));
            Log(rp.id,'  освободили кусок заявки track_order '||tor.id ||' робота '||tor.robot_id||' на трек с '||tor.npp_from||' на трек с  '||npp_tmp__);
            update track_order set npp_from=npp_tmp__ where robot_id=rid_;
          end loop;
          -- удаляем всю заявку
          for tor in (select *  from track_order where robot_id=rid_ and npp_from=npp_cur__ and npp_from=npp_to) loop
            Log(rp.id,'  удалили заявку track_order '||tor.id ||' робота '||tor.robot_id||' на трек с '||tor.npp_from||' по '||tor.npp_to||' робот мешал '||tor.robot_stop_id);
            delete from track_order where robot_id=rid_;
          end loop;

        elsif tr.locked_by_robot_id<>rid_ then
          barrier_robot_id:=tr.locked_by_robot_id;
          if npp_old__<0 then
            Log(rp.id,'  ERROR - заблокировано другим роботом');
            ft:=Form_Track_Order(rid_, npp_from_sorb__, npp_to_sorb__, dir_,tr.locked_by_robot_id );
            if not ft and not IsIgnoreBufTrackOrder then
               return -1;
            end if;
            TrackLockPrim(rp.id, rid_);
            return npp_old__;
          else
            ft:=Form_Track_Order(rid_, tr.npp, npp_to_sorb__, dir_,tr.locked_by_robot_id );
            if not ft and not IsIgnoreBufTrackOrder then
               return -1;
            end if;
            TrackLockPrim(rp.id, rid_);
            npp_old__:=add_track_npp(rp.id, npp_old__,rp.spacing_of_robots,get_another_direction(dir_));
            return npp_old__;
          end if;

        end if;
      end loop;
      if not npp_to_was_locked__ and npp_cur__=npp_to_ then
        npp_to_was_locked__:=true;
      end if;
      npp_old__:=npp_cur__;
      exit when npp_cur__=npp_to_sorb__ and npp_to_was_locked__;
      npp_cur__:=add_track_npp(rp.id,npp_cur__,1,dir_);
      Log(rp.id,'  tr.npp_cur__='||npp_cur__);

    end loop;

    TrackLockPrim(rp.id, rid_);

    -- удаляем заявки на трек, если были, раз сюда дошли, то
    for tt in (select * from track_order where robot_id=rid_) loop
       delete from track_order where robot_id=rid_;
       Log(rp.id,'  удалили заявку track_order '||tt.id ||' робота '||tt.robot_id||' на трек с '||tt.npp_from||' по '||tt.npp_to||' робот мешал '||tt.robot_stop_id);
    end loop;
    return npp_to_;
  end loop;
end;

-- добавить промежуточную точку для робота, если он поддерживает
procedure add_check_point(rp_id_ number,sorb_ number, robot_id_ number,dir_ number,tr_npp_ number) is
  tr_ number;
  --cnt number;
begin
  for ci in (select * from command_inner where robot_id=robot_id_ and state in (0,1,3,4) and nvl(check_point,-1)>=0) loop
    tr_:=add_track_npp(rp_id_, tr_npp_ ,sorb_, get_another_direction(dir_));
    --select count(*) into cnt from command_inner_checkpoint where
    insert into command_inner_checkpoint(command_inner_id,npp)
    values(ci.id, tr_);
  end loop;
end;


-- вызывается из триггера при смене текущего трека; нужно передавать rp_id_, чтобы не было мутации
procedure Unlock_Track(robot_id_ in number, rp_id_ number, npp_from_ in number,npp_to_ in number,dir_ in number) is
  npp2 number;
  npp1_ number;
  npp2_ number;
  tr_id number;
  tr_npp number;
  tr_locked_by_robot_id number;
  anroid number;
  nrs number;
  is_loop_exit number;
  errmm__ varchar2(1000);
  ch_p_ number;

begin
  for rrp in (select rp.id rpid_, spacing_of_robots sorb, max_npp , repository_type rpt, num_of_robots
              from repository_part rp
              where rp.id=rp_id_) loop
    Log(rrp.rpid_,'unlock_track: пришла npp_from_='||npp_from_||'; npp_to_='||npp_to_||'; direction='||dir_||'; robot.id='||robot_id_);
    if npp_from_=npp_to_ then
      Log(rrp.rpid_,'  нет смысла сразу npp_from_='||npp_from_||'; npp_to_='||npp_to_||'; direction='||dir_||'; robot.id='||robot_id_);
      return;
    end if;
    npp2:=add_track_npp(rrp.rpid_, npp_to_ ,1, get_another_direction(dir_));
    npp1_:=add_track_npp(rrp.rpid_, npp_from_ ,rrp.sorb, get_another_direction(dir_));
    npp2_:=add_track_npp(rrp.rpid_, npp2 ,rrp.sorb, get_another_direction(dir_));
    if rrp.rpt=0 and npp_to_<=rrp.sorb and dir_=1 then
      null;
    elsif rrp.rpt=0 and npp_to_>=rrp.max_npp-rrp.sorb and dir_=0 then
      null;
    else
      tr_npp:= npp1_;
      loop
        select id, locked_by_robot_id
        into tr_id, tr_locked_by_robot_id
        from track
        where npp=tr_npp and repository_part_id=rrp.rpid_;
        if nvl(tr_locked_by_robot_id,0) not in (robot_id_ ,0) then
          errmm__:='ERROR - Ошибка ошибка разблокировки трека '||tr_npp||'! locked by '||nvl(tr_locked_by_robot_id,0);
          log(rrp.rpid_, errmm__);
          raise_application_error (-20012, errmm__, TRUE);
        end if;
        update track set locked_by_robot_id=0 where id=tr_id;
        -- освобождаем заявки их удовлетворяя
        for zay in (select * from track_order
                    where tr_npp = npp_from
                          and robot_id<>robot_id_
                          and repository_part_id=rrp.rpid_
                    order by id ) loop
          Log(rrp.rpid_,'  есть заявка ='||zay.id||' - освобождаем');
          update track set locked_by_robot_id=zay.robot_id
          where id=tr_id;
          add_check_point(zay.repository_part_id,rrp.sorb,zay.robot_id,zay.direction,tr_npp);
          if zay.npp_from=zay.npp_to then -- нет нужды в этой заявке - удаляем ее
            delete from track_order where id=zay.id;
            Log(rrp.rpid_,'  уже все выбрано по заявке - удаляем');
          else -- еще есть нужда в заявке - уменьшаем ее размер
            if zay.npp_from=tr_npp then
               Log(rrp.rpid_,'  уменьшаем заявку трек '||tr_npp);
               npp1_:=add_track_npp(rrp.rpid_, tr_npp ,1, zay.direction);
               update track_order
               set npp_from=npp1_ where id=zay.id;
            end if;
          end if;
        end loop;

        get_next_npp(rrp.rpt, rrp.max_npp, tr_npp, npp2_, dir_,tr_npp,is_loop_exit );
        exit when is_loop_exit=1;
      end loop;
    end if;
  end loop;
end;

-- пытаемся заблокировать трек в указанном месте + ореол вокруг робота
function Try_Track_Lock_Robot_Around(rid_ number, npp_ number) return number is
  errm__ varchar2(1000);
  ttl__ number;
  npp_from_sorb__ number;
  npp_to_sorb__ number;
  npp_cur__ number;
begin
  for rr in (select r.*, num_of_robots nor , rp.id rp_id, spacing_of_robots
             from robot r, repository_part rp
             where r.id=rid_ and repository_part_id=rp.id) loop
    Log(rr.rp_id,'Try_Track_Lock_Robot_Around - Блокируем вокруг трека '||npp_||' робота '||rid_);
    npp_from_sorb__:=add_track_npp(rr.rp_id, npp_,rr.spacing_of_robots, 0);
    npp_to_sorb__:=add_track_npp(rr.rp_id, npp_,rr.spacing_of_robots,1);
    npp_cur__:=npp_from_sorb__;
    loop
      for tr in (select * from track where repository_part_id=rr.rp_id and npp=npp_cur__) loop
        if tr.locked_by_robot_id =0 then
          update track set locked_by_robot_id=rid_ where id=tr.id;
        elsif tr.locked_by_robot_id<>rid_ then
          Log(rr.rp_id,'  ERROR - заблокировано другим роботом');
          return 0;
        end if;
      end loop;
      exit when npp_cur__=npp_to_sorb__;
      npp_cur__:=add_track_npp(rr.rp_id,npp_cur__,1,1);
    end loop;
  end loop;
  return 1;
end;

-- заблокировано ли вокруг? (если maybe_locked_==1, то еще и нет ли помех для блокировки если нужно?)
function Is_Track_Locked_Around(rid_ number, npp_ number, maybe_locked_ number default 0) return number is
  ll number;
  npp_from_sorb__ number;
  npp_to_sorb__ number;
  npp_cur__ number;
begin
  for r in (select * from robot where id=rid_) loop
    for rp in (select repository_type, id, max_npp, spacing_of_robots sorb, num_of_robots
               from repository_part rp where id=r.repository_part_id) loop
      npp_from_sorb__:=add_track_npp(r.repository_part_id, npp_,rp.sorb, 0);
      npp_to_sorb__:=add_track_npp(r.repository_part_id, npp_,rp.sorb,1);
      --dbms_output.put_line(npp_from_sorb__||' '||npp_to_sorb__);
      npp_cur__:=npp_from_sorb__;
      loop
        --dbms_output.put_line(' npp_cur__='||npp_cur__);
        select locked_by_robot_id into ll from track where repository_part_id=rp.id and npp=npp_cur__;
        if ll<>r.id  then -- ошибка
          if maybe_locked_=0 then
            return 0; -- путь не готов - ОШИБКА!!!
          else -- параметр ф-ии с возможностью блокировки
            if ll<>0 then
              return 0; -- блокирован иным роботом
            end if;
          end if;
        end if;
        exit when npp_cur__=npp_to_sorb__;

        if rp.repository_type =1 then -- для кольцевого склада
          if npp_cur__=rp.max_npp then
             npp_cur__:=0;
          else
             npp_cur__:=npp_cur__+1;
          end if;
        else  -- для линейного
          if npp_cur__<rp.max_npp then
             npp_cur__:=npp_cur__+1;
          else
             exit; -- выход из цикла
          end if;
        end if;
      end loop;
    end loop;
  end loop;
  return 1; -- все проверено, мин нет
end;

-- проверяем - заблокирован ли ореол вокруг робота?
function Check_Lock_Robot_Around(rid_ number, npp_ number) return number is
  ttl__ number;
  errm__ varchar2 (1000);
begin
  for rr in (select r.*, num_of_robots nor from robot r, repository_part rp
             where r.id=rid_ and repository_part_id=rp.id) loop
    --Log(rr.repository_part_id,'Check_Lock_Robot_Around -  вокруг трека '||npp_||' робота '||rid_);
    if rr.nor=1 then  -- склад с одним роботом
      if Is_Track_Locked_Around(rid_, npp_)=0 then
        Log(rr.repository_part_id,'  вокруг трека не заблокировано, блокируем!');
        ttl__:=Try_Track_Lock_Robot_Around(rid_, npp_);
      else
        --Log(rr.repository_part_id,'  вокруг трека уже заблокировано');
        null;
      end if;
      return 1;
    else  -- склад с несколькими роботами
      if Is_Track_Locked_Around(rid_, npp_)=0 then
        errm__:='  ERROR - не получилось заблокировать вокруг трека '||npp_||' робота '||rid_;
        obj_ask.global_error_log(obj_ask.error_type_robot_rp,rr.repository_part_id,rid_,errm__);
        Log(rr.repository_part_id,errm__);
        raise_application_error (-20012, errm__, TRUE);
        return 0;
      else
        --Log(rr.repository_part_id,'  успешно заблокировали');
        return 1;

      end if;
    end if;
  end loop;

end;

-- креш-тест робота по огурцу - такт
procedure crash_test_tact(rpid_ number) is
  cnt number;
begin
    select count(*) into cnt
    from command where command_type_id=1 and rp_src_id=rpid_ and rp_dest_id=rpid_ and state not in (5,2);
    if cnt <=5 then -- есть куда напхать команд
      -- сколько свободных ячеек универсальных
      select count(*) into cnt from cell
      where hi_level_type=1 and is_full=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id);
      if cnt >=1 then
        for ci in (select * from cell
                   where hi_level_type=1 and is_full=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                   order by DBMS_RANDOM.random) loop
          for cco in (select * from cell
                   where hi_level_type=1  and is_full>=1 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                   order by /*abs(track_npp-ci.track_npp) desc,*/ DBMS_RANDOM.random) loop
            insert into command(command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, container_id)
            values(1,rpid_,cco.sname, rpid_, ci.sname,1, 0);
            exit;
          end loop;
          exit;
        end loop;
      end if;
    end if;
    commit;
end;

-- креш-тест Рязани
procedure crash_test_rzn is
  cnt number;
  rpid_ number;
begin
  rpid_:=1;
  select count(*) into cnt
  from command where command_type_id=1 and state not in (5,2);
  if cnt <=5 then -- есть куда напхать команд
      cnt:=DBMS_RANDOM.value(0,1);
      if cnt<0.3 then -- приход
        -- сколько свободных ячеек приема
        select count(*) into cnt from cell
        where hi_level_type=9 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id);
        if cnt >=1 then
          for ci in (select * from cell
                     where hi_level_type=9 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                     order by DBMS_RANDOM.random) loop
            for cco in (select * from cell
                     where hi_level_type=1  and is_full<=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                     order by /*abs(track_npp-ci.track_npp) desc,*/ DBMS_RANDOM.random) loop
              insert into command(command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, container_id)
              values(1,rpid_,ci.sname, rpid_, cco.sname,1, 0);
              exit;
            end loop;
            exit;
          end loop;
        end if;
      elsif cnt>=0.6 then -- расход
        select count(*) into cnt from cell
        where hi_level_type=15 and is_full<=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id);
        if cnt >=1 then
          for ci in (select * from cell
                     where hi_level_type=15 and is_full<=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                     order by DBMS_RANDOM.random) loop
            for cco in (select * from cell
                     where hi_level_type=1  and is_full>0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                     order by /*abs(track_npp-ci.track_npp) desc,*/ DBMS_RANDOM.random) loop
              insert into command(command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, container_id)
              values(1,rpid_,cco.sname, rpid_, ci.sname,1, 0);
              exit;
            end loop;
            exit;
          end loop;
        end if;
      else -- возврат
      -- сколько свободных ячеек универсальных
      select count(*) into cnt from cell
      where hi_level_type=15 and is_full>0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id);
      if cnt >=1 then
        for ci in (select * from cell
                   where hi_level_type=15 and is_full>0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                   order by DBMS_RANDOM.random) loop
          for cco in (select * from cell
                   where hi_level_type=1  and is_full<=0 and repository_part_id=rpid_ and not exists (select * from cell_cmd_lock where cell_id=cell.id)
                   order by /*abs(track_npp-ci.track_npp) desc,*/ DBMS_RANDOM.random) loop
            insert into command(command_type_id, rp_src_id, cell_src_sname, rp_dest_id, cell_dest_sname, priority, container_id)
            values(1,rpid_,ci.sname, rpid_, cco.sname,1, 0);
            exit;
          end loop;
          exit;
        end loop;
      end if;
    end if;
    commit;
  end if;
end;

-- сколько уже времени в секундах исполняется команда?
function Get_Cmd_RP_Time_Work(crpid_ number) return number is
  delta__ number;
  max_d__ number;
begin
  max_d__:=1/(24*10);
  for crp__ in (select * from command_rp where id=crpid_) loop
     delta__:=sysdate-nvl(crp__.date_time_begin,sysdate);
     if delta__>=max_d__ then
       return round(max_d__*24*60*60);
     else
       return round(delta__*24*60*60);
     end if;
  end loop;
  return -1;
end;

-- получить порядковый № команды перемещения контейнеров в огурце после минимально активной
function Get_Cmd_RP_Order_After_Min(rpid_ number, cmdrpid_ number) return number is
  min__ number;
  oo__ number;
begin
  min__:=Get_Cmd_RP_Min_NS_ID(rpid_);
  if min__=cmdrpid_ then
    return 0;
  end if;
  if min__>0 then
    oo__:=0;
    for tt in (select * from sarmat.command_rp t
               where rp_id= rpid_
                    and command_type_id=3
                    and id>=min__
               order by id) loop
        if tt.id=cmdrpid_ then
          return oo__;
        end if;
        oo__:=oo__+1;
    end loop;
  end if;
  return -1;
end;

-- получить порядковый № команды перемещения контейнеров в огурце после минимально активной в заданном приоритете
function Get_Cmd_RP_Order_After_Min(rpid_ number, pri_ number, cmdrpid_ number) return number is
  min__ number;
  oo__ number;
begin
  min__:=Get_Cmd_RP_Min_NS_ID(rpid_, pri_);
  if min__=cmdrpid_ then
    return 0;
  end if;
  if min__>0 then
    oo__:=0;
    for tt in (select * from sarmat.command_rp t
               where rp_id= rpid_
                    and command_type_id=3
                    and priority=pri_
                    and id>=min__
               order by id) loop
        if tt.id=cmdrpid_ then
          return oo__;
        end if;
        oo__:=oo__+1;
    end loop;
  end if;
  return -1;
end;


-- получить минимальный ID активной команды в указанном огурце
function Get_Cmd_RP_Min_NS_ID(rp_id_ number) return number is
begin
  for tt in (select id from command_rp t
             where rp_id= rp_id_
                  and state in (0,1,3)
                  and command_type_id=3
                  and robot_id is null
             order by id) loop
    return tt.id;
  end loop;
  return -1;
end;

-- получить минимальный ID активной команды в указанном огурце в указанном приоритете
function Get_Cmd_RP_Min_NS_ID(rp_id_ number, pri_ number) return number is
begin
  for tt in (select id from command_rp t
             where rp_id= rp_id_
                  and state in (0,1,3)
                  and command_type_id=3
                  and priority=pri_
                  and robot_id is null
             order by id) loop
    return tt.id;
  end loop;
  return -1;
end;

-- для транзитного склада взять ячейку большого размера если нет малой.
function assign_tmp_cell_any_size(rpl_id number,cmrp_npp_src number) return varchar2 is
  cnt number;
begin
  select min(abs((t.npp-cmrp_npp_src))) into cnt
  from cell c, shelving s, track t
  where c.is_full=0
        and nvl(c.blocked_by_ci_id,0)=0
        and c.shelving_id=s.id
        and s.track_id=t.id
        and hi_level_type=10
        and is_error=0
        and not exists (select * from cell_cmd_lock where cell_id=c.id)
        and cell_size=0
        and t.repository_part_id=rpl_id;
  for cnn in (select sname
              from cell c, shelving s, track t
              where c.is_full=0
                    and not exists (select * from cell_cmd_lock where cell_id=c.id)
                    and nvl(c.blocked_by_ci_id,0)=0
                    and c.shelving_id=s.id
                    and s.track_id=t.id
                    and is_error=0
                    and cell_size=0
                    and hi_level_type=10
                    and t.repository_part_id=rpl_id
                    and abs(t.npp-cmrp_npp_src)=cnt
              order by orientaition desc) loop
    return (cnn.sname);
  end loop;
  return ('');
end;

-- заблокирована ли трек ячейки?
function is_cell_cmd_track_lock(cell_id_ number) return number is
  tr_id_ number;
begin
  select track_id into tr_id_ from shelving sh, cell where cell.id=cell_id_ and shelving_id=sh.id;
  for t in (select track_id
            from cell_cmd_lock ccl, cell cl, shelving sh
            where ccl.cell_id=cl.id and cl.shelving_id=sh.id and sh.track_id=tr_id_) loop
    return 1; -- трек ячейки заблокирован cell_cmd_lock
  end loop;
  -- проверяем на команды
  for cc in (select * from command_rp crp where  crp.state in (1,3) and nvl(track_dest_id,-1)=tr_id_) loop
    return 1; -- трек ячейки заблокирован command_rp неявно
  end loop;
  return 0; -- трек ячейки незаблокирован cell_cmd_lock
end;

-- преобразование групповых операций перемещения в обычные
procedure Group_Op_To_Simple_CRP(rp_id_ number) is
  cnt__ number;
  cell_to__ varchar2(100);
  track_id_to__ number;
  npp_dest_new__ number;
  cell_id_new_ number;
  cnt_type__ number;
  msg_ varchar2(500);
  otf_ number;
begin
  for cmrp in (select /*+RULE*/ cr.* from command_rp cr, cell c, cell_type ct
               where rp_id=rp_id_ and state=1
                     and cr.cell_src_id =c.id and c.hi_level_type=ct.id
                     and cr.command_type_id=7
               order by PRIORITY desc, ct.obligotary_to_free desc, cr.id) loop
    log(rp_id_,'Group_Op_To_Simple_CRP - есть команда для преобразования '||cmrp.id);
     -- вначале смотрим, есть ли свободная ячейка из группы-приемника
    select obligotary_to_free into otf_ from cell_type
    where id=(select hi_level_type from cell where id=cmrp.cell_src_id);
    execute immediate 'select count(*) '||cmrp.sql_text_for_group into cnt__;
    if cnt__<>0 then -- есть подходящие ячейки
      if otf_=0 then -- не обязательно резко освобождать, смотрим, а не заблокировано ли
        execute immediate 'select count(*)  '||cmrp.sql_text_for_group||' and sarmat.obj_rpart.is_cell_cmd_track_lock(id)=0' into cnt__;
        if cnt__=0 then
          log(rp_id_,'Group_Op_To_Simple_CRP - все заблокировано командами для транзитной передачи для cmd_rp.id='||cmrp.id);
          continue; -- переходим к следующей команде
        end if;
      end if;
      execute immediate 'select sname  '||cmrp.sql_text_for_group||' and rownum=1'
      into cell_to__;
      log(rp_id_,'   есть подходящая ячейка '||cell_to__);
      track_id_to__:=get_track_id_by_cell_and_rp(cmrp.rp_id, cell_to__);
      npp_dest_new__:=get_track_npp_by_cell_and_rp(cmrp.rp_id, cell_to__);
      log(rp_id_,'   track_id_to__='||track_id_to__||' npp_dest_new__='||npp_dest_new__);
      cell_id_new_:=get_cell_id_by_name(cmrp.rp_id,cell_to__);
      log(rp_id_,'   cell_id_new_='||cell_id_new_);
      update command_rp
      set cell_dest_sname=cell_to__,
          track_dest_id=track_id_to__,
          cell_dest_id=cell_id_new_,
          npp_dest=npp_dest_new__,
          ideal_cost=nvl(service.calc_ideal_crp_cost(rp_id , cell_src_id , cell_id_new_),0),
          command_type_id=3
      where id=cmrp.id;
      log(rp_id_,'   успешно закоммитили '||SQL%ROWCOUNT||' записей');
      commit;
    else
      log(rp_id_,'  fc: все транзитные ячейки заняты ');
      if otf_=1 then
        -- обязательно надо освободить, освобождаем
        -- но вначале определяем тип контейнера на платформе
        log(rp_id_,'  fc: а освобождать надо ');
        begin
          select nvl(type,0) into cnt_type__ from container
          where id=(select container_id from command where id=cmrp.command_id);
        exception when others then
          cnt_type__:=0; -- не знаем какой, считаем, что большой
        end;

        begin
          cell_to__:='';
          select min(abs((t.npp-cmrp.npp_src))) into cnt__
          from cell c, shelving s, track t
          where c.is_full=0
                and nvl(c.blocked_by_ci_id,0)=0
                and c.shelving_id=s.id
                and s.track_id=t.id
                and not exists (select * from cell_cmd_lock where cell_id=c.id)
                and hi_level_type=10
                and cell_size=cnt_type__
                and is_error=0
                and t.repository_part_id=rp_id_;
          for ncell in (select sname
                        from cell c, shelving s, track t
                        where c.is_full=0
                              and nvl(c.blocked_by_ci_id,0)=0
                              and c.shelving_id=s.id
                              and s.track_id=t.id
                              and cell_size=cnt_type__
                              and not exists (select * from cell_cmd_lock where cell_id=c.id)
                              and hi_level_type=10
                              and not exists (select * from command_rp where rp_id=rp_id_ and cell_src_sname=c.sname and state in (0,1,3))
                              and t.repository_part_id=rp_id_
                              and abs(t.npp-cmrp.npp_src)=cnt__
                              and is_error=0
                        order by orientaition desc) loop
            cell_to__:=ncell.sname;
            exit;
          end loop;

        exception when others then
          cell_to__:=assign_tmp_cell_any_size(rp_id_,cmrp.npp_src );
        end;

        if cell_to__ is null then
          cell_to__:=assign_tmp_cell_any_size(rp_id_,cmrp.npp_src );
        end if;

        if cell_to__ is null then
          msg_:='  Error - Нет места в транзитном складе!';
          log(rp_id_,msg_);
          obj_ask.global_error_log(obj_ask.error_type_rp,rp_id_,null,msg_);

        else
          log(rp_id_,'  fc: временно перемещаем в '||cell_to__);
          track_id_to__:=get_track_id_by_cell_and_rp(cmrp.rp_id, cell_to__ );
          npp_dest_new__:=get_track_npp_by_cell_and_rp(cmrp.rp_id, cell_to__);
          begin
            -- добавляем новую команду
            --log(rp_id_,'  fc: '||cmrp.command_type_id||','|| cmrp.rp_id||','|| cell_to__||','||
            --  cmrp.cell_dest_sname||','|| cmrp.priority||','|| cmrp.state||','|| cmrp.command_id||','|| track_id_to__||','||
            --  cmrp.track_dest_id||','|| cmrp.sql_text_for_group||','|| get_cell_id_by_name(cmrp.rp_id, cell_to__)||','|| cmrp.cell_dest_id||','||
            --  npp_dest_new__||','|| cmrp.npp_dest||','|| cmrp.container_id);
            insert into command_rp (command_type_id, rp_id, cell_src_sname,
              cell_dest_sname, priority, state, command_id, track_src_id,
              track_dest_id, sql_text_for_group, cell_src_id, cell_dest_id,
              npp_src, npp_dest, container_id)
            values (cmrp.command_type_id, cmrp.rp_id, cell_to__,
              cmrp.cell_dest_sname, cmrp.priority, cmrp.state, cmrp.command_id, track_id_to__,
              cmrp.track_dest_id, cmrp.sql_text_for_group, get_cell_id_by_name(cmrp.rp_id,cell_to__), cmrp.cell_dest_id,
              npp_dest_new__, cmrp.npp_dest, cmrp.container_id);
            --log(rp_id_,'  fc: успешно добавили command_rp');
            -- изменяем старую
            update command_rp
            set cell_dest_sname=cell_to__,
                is_to_free=1,
                track_dest_id=track_id_to__,
                cell_dest_id=get_cell_id_by_name(cmrp.rp_id,cell_to__),
                npp_dest=npp_dest_new__,
                command_type_id=3
            where id=cmrp.id;
            commit;
          exception when others then
            msg_:='  ERROR временного перемещения fc: '||SQLERRM;
            rollback;
            obj_ask.global_error_log(obj_ask.error_type_rp,rp_id_,null,msg_);
            log(rp_id_,msg_);
          end;
        end if;
      else
        --msg_:='  ERROR временного перемещения fc: странно, освобождать не надо ';
        --obj_ask.global_error_log(obj_ask.error_type_rp,rp_id_,null,msg_);
        --log(rp_id_,msg_);
        cell_to__:='';
        --exit;
      end if;

      null;
    end if;
  end loop;  -- для cmrp

end;

-- основная функция, которая вызывается из фоновой процедуры C# бесконечного цикла
procedure Form_Cmds(rpid_ number) is
begin
  log(rpid_,'');
  log(rpid_,'*****************************************');
  log(rpid_,'Начало FormCmds для склада');
  if Is_Npp_Actual_Info(rpid_)=0 then
    log(rpid_,'ERROR - устаревание информации о местоположении роботов!');
    return;
  end if;

  for rpl in (select distinct rp.id, rp.repository_type rt, is_cell_move_after_cmd, is_robot_need_InitY,
               rp.spacing_of_robots sorb, rp.cmd_transfer_enabled , rp.max_npp,
               rp.num_of_robots
              from repository_part rp, robot r
              where r.repository_part_id=rp.id
                    and obj_robot.Is_Robot_Ready_For_Cmd_Inner(r.id)=1
                    and (rpid_=0 or rp.id=rpid_)  ) loop
    log(rpid_,'   Вошли в цикл');
    if rpl.is_cell_move_after_cmd=1 then
      Move_Robot_Away_If_Ness(rpl.id); -- двигаем роботов от рабочего стола после UNLOAD, если указано в настройках АСК
      log(rpl.id,'  Move_Robot_Away_If_Ness прошло');
    end if;

    if rpl.is_robot_need_InitY=1 then
      InitY_If_Ness(rpl.id);
      log(rpl.id,'  InitY_If_Ness прошло');
    end if;

    for rep in (select id from repository where is_group_cmd=1) loop
      Group_Op_To_Simple_CRP(rpl.id);
      log(rpl.id,'  Group_Op_To_Simple_CRP прошло');
    end loop;

    Set_New_Cmd_RPs(rpl.id);
    log(rpl.id,'  Set_New_Cmd_RPs прошло');

    for rr in (select id from robot where repository_part_id=rpid_) loop
      if obj_robot.Is_Robot_Ready_For_Cmd_Inner(rr.id)=1 then
        Run_Cmd_Parts(rr.id); -- до
      end if;
    end loop;
    log(rpl.id,'  Run_Cmd_Parts прошло');

    commit;

  end loop;

end;

-- есть ли какие-то роботы в огурце с командами?
function Get_RP_CIA_State(rp_id_ number) return number is
  -- = 0 -все роботы свободные без команд
  -- = 1 -есть какие-то  роботы с командами
begin
  for rr in (select * from robot where repository_part_id=rp_id_) loop
    if nvl(rr.command_inner_assigned_id,0)<>0 then
       return 1;
    end if;
  end loop;
  return 0;
end;

-- есть ли какие-то роботы в огурце активные (не готовы и не в починке)?
function Get_RP_Robots_State(rp_id_ number) return number is
  -- = 0 -все роботы свободны или в ремонте
  -- = 1 -есть какие-то работающие роботы
begin
  for rr in (select * from robot where repository_part_id=rp_id_) loop
    if rr.state not in (0,6) then
       return 1;
    end if;
  end loop;
  return 0;
end;

-- есть ли на подскладе какие-то назначенные на роботов команды перемещения контейнеров
function Get_RP_Command_State(rpid_ number) return number is
  -- = 0 -нет ни одной команды ни на одного робота
  -- = 1 -есть какие-то команды
begin
  for rr in (select * from robot where repository_part_id=rpid_) loop
    if obj_robot.Is_Robot_Ready_For_Cmd(rr.id, true)=0 then
      return 1;
    end if;
  end loop;
  return 0;
end;

-- сколько в огурце роботов?
function Get_RP_Num_Of_robots(rpid_ number) return number is
begin
  for rp in (select num_of_robots from repository_part where id=rpid_) loop
    return rp.num_of_robots;
  end loop;
  return 0;
end;

-- получить минимальное расстояние между роботами в огурце
function Get_RP_Spacing_Of_robots(rpid_ number) return number is
begin
  for rp in (select spacing_of_robots from repository_part where id=rpid_) loop
    return rp.spacing_of_robots;
  end loop;
  return 0;
end;

-- получить имя огурца
function Get_RP_Name(rpid_ number) return varchar2 is
begin
  for rp in (select name from repository_part where id=rpid_) loop
    return rp.name;
  end loop;
  return '';
end;


-- переблкоируем вокруг робота
procedure ReLock_Robot_Around(rid_ number, npp_ number) is
  rp_id__ number;
  errm__ varchar2(1000);
begin
  rp_id__:=obj_robot.Get_Robot_RP_ID(rid_);
  update track set locked_by_robot_id=0 where  locked_by_robot_id=rid_;
  if Try_Track_Lock_Robot_Around(rid_ , npp_ )=1 then
      log(rp_id__,'  успешно заблокировали вокруг нового робота '||rid_||' npp='||npp_);
      commit;
  else
      errm__:='  ERROR - не могу заблокировать путь для нового робота '||rid_||' npp='||npp_;
      log(rp_id__,errm__);
      raise_application_error (-20012, errm__, TRUE);
  end if;
end;

-- проверяем на корректность блокировки для команд роботов, которые находятся в ожидании решения проблемы
procedure Check_WPR_Lock(rpid_ number) is
  ci_npp_dest_ number;
  lt_ number;
  brr_ number;
  errm_ varchar2(400);
  new_dir_ number;
begin
  --return;
  for rr in (select * from robot where nvl(wait_for_problem_resolve,0)=1 and repository_part_id=rpid_) loop
    for ci in (select * from command_inner where id=rr.command_inner_id) loop
      ci_npp_dest_:=obj_robot.Get_Cmd_Inner_Npp_Dest(ci.id,1);
      if is_track_locked(rr.id, ci_npp_dest_, ci.direction)=0 then
        obj_robot.log(rr.id,'Ошибка проверки блокировки робота, находящегося в режиме ожидания решения проблемы is_track_locked('||rr.id||', '||ci_npp_dest_||', '||ci.direction||')=0');
        if is_track_locked(rr.id, ci_npp_dest_, ci.direction,1)=1 then
          obj_robot.log(rr.id,'  но можно заблокировать до куда надо');
          lt_:=Try_Track_Lock(rr.id ,  ci_npp_dest_, ci.direction ,  true, brr_);
          if lt_<>ci_npp_dest_ then
            errm_:='  ERROR - говорит, что можно заблокировать, а не блокирует, пытается только до '||lt_;
            obj_robot.log(rr.id,errm_);
            raise_application_error (-20012, errm_, TRUE);
          end if;
        else
          obj_robot.log(rr.id,'  и нельзя заблокировать куда надо, меняем');
          new_dir_:=Get_Another_Direction(ci.direction);
          if is_track_locked(rr.id, ci_npp_dest_, new_dir_)=1 then
            obj_robot.log(rr.id,'  в другом направлении и так заблокировано, просто меняем направление команды, которая в ожидании решении проблемы');
            obj_robot.change_wpr_dir(ci.id,new_dir_);
          else
            if is_track_locked(rr.id, ci_npp_dest_, new_dir_,1)=1 then
               obj_robot.log(rr.id,'  но можно заблокировать до куда надо c другой стороны');
               lt_:=Try_Track_Lock(rr.id ,  ci_npp_dest_, new_dir_ ,  true, brr_);
               if lt_<>ci_npp_dest_ then
                 errm_:='  ERROR - говорит, что можно заблокировать с другой стороны, а не блокирует, пытается только до '||lt_;
                 obj_robot.log(rr.id,errm_);
                 raise_application_error (-20012, errm_, TRUE);
               end if;
               obj_robot.change_wpr_dir(ci.id,new_dir_);
            else
                 errm_:='  ERROR - нельзя заблокировать ни с какой из сторон для робота, находящегося в режиме решения проблемы';
                 obj_robot.log(rr.id,errm_);
                 raise_application_error (-20012, errm_, TRUE);
            end if;

        end if;
      end if; -- maybe_locked_ number default 0, check_ask_1_robot number default 0) return number is
      end if;
    end loop;
  end loop;
  commit;
end;


-- проверяем корректность нахождения робота в треке, если что не так, то raise
procedure Check_New_Robot_Npp_Correct(rid_ number, npp_ number) is
  rp_id__ number;
  RPCS__ number;
  errm__ varchar2(1000);
  cnt__ number;
  sor__ number;
begin
  obj_robot.log(rid_,'Check_New_Robot_Npp_Correct - начало npp_='||npp_);
  rp_id__:=obj_robot.Get_Robot_RP_ID(rid_);
  --log(rp_id__,'Check_New_Robot_Npp_Correct - начало ');
  RPCS__:=Get_RP_Command_State(rp_id__);
  if RPCS__=0 then  -- вариант, когда команд нет
    obj_robot.log(rid_,'    RPCS__=0 - команд нет');
    --obj_robot.log(rid_,'  RPCS__=0 - команд нет');
    select count(*) into cnt__ from track where locked_by_robot_id =rid_;
    --obj_robot.log(rid_,'  cnt__='||cnt__);
    if cnt__=0 then -- новый робот встает на путь
      log(rp_id__,'Ставим нового робота '||rid_||' на путь!');
      if Try_Track_Lock_Robot_Around(rid_ , npp_ )=1 then
        log(rp_id__,'  успешно заблокировали вокруг нового робота '||rid_);
      else
        errm__:='  ERROR - не могу заблокировать путь для нового робота '||rid_;
        log(rp_id__,errm__);
        raise_application_error (-20012, errm__, TRUE);
      end if;
    else -- уже есть что-то заблокированное этим роботом
        for rp in (select *   from repository_part where id=rp_id__) loop
          if cnt__>(rp.spacing_of_robots*2+1) then -- слишком много заблокировано
            log(rp_id__,'  ERROR - слишком много заблокировано роботом '||rid_||'. Поэтому сбрасываем блокировку от этого робота');
            ReLock_Robot_Around(rid_, npp_);
          else -- заблокировано не больше, чем надо. Но там ли?
            --log(rp_id__,'    спрашиваем Is_Track_Locked_Around ');
            if Is_Track_Locked_Around(rid_ , npp_ ) =0 then -- не заблокировано там где надо
              log(rp_id__,'  ERROR - не заблокировано роботом '||rid_||' вокруг '||npp_||'. Поэтому сбрасываем старую блокировку и переблокируем по-новому!');
              ReLock_Robot_Around(rid_, npp_);
            end if;
          end if;
        end loop;
    end if;
  else  -- вариант, когда есть реальные команды
    obj_robot.log(rid_,'    Есть реальные команды');
    if Get_RP_Robots_State(rp_id__)=0 then -- все роботы по подскладу простаивают
        obj_robot.log(rid_,'    все роботы по подскладу простаивают');
        if Get_RP_CIA_State(rp_id__)=0 then -- нет назначенных команд
          for rr in (select * from robot where id=rid_ and  state=0 and obj_rpart.is_robot_lock_bad(id)=1) loop
              if Is_Track_Locked_Around(rr.id, npp_,1)=1  then -- теоретически можно заблокировать
                errm__:='ERROR - для робота '||rr.id||' плохая блокировка, но можно попытаться восстановить';
                obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                log(rp_id__,errm__);
                ReLock_Robot_Around(rr.id, npp_);
              else
                errm__:='ERROR - для робота '||rr.id||' плохая блокировка, восстановить нельзя, т.к. заблокировано иным роботом '||npp_;
                obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                log(rp_id__,errm__);
              end if;
          end loop;
        else -- есть назначенные команды, действуем аккуратней!
          -- роботы без cmd_inner стоящие
          for rr in (select * from robot where id=rid_ and state=0
                       and obj_rpart.is_robot_lock_bad(id)=1 and nvl(command_inner_assigned_id,0)=0) loop
            if Is_Track_Locked_Around(rr.id, npp_)=0  then
               if Is_Track_Locked_Around(rr.id, npp_,1)=1 then
                 errm__:='ERROR - для робота '||rr.id||' плохая блокировка и есть команды RP, но можно попытаться восстановить';
                 obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                 log(rp_id__,errm__);
                 ReLock_Robot_Around(rr.id, npp_);
                 delete from track_order where robot_id=rr.id;
               else
                 errm__:='ERROR - для робота '||rr.id||' плохая блокировка, восстановить нельзя, т.к. заблокировано иным роботом '||npp_;
                 obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                 log(rp_id__,errm__);
               end if;
            end if;
          end loop;

          -- роботы в режиме решения проблемы стоящие, и без промежуточных точек
          for rr in (select * from robot where id=rid_ and state=0
                       /*and is_robot_lock_bad(id)=1*/ and nvl(command_inner_id,0)<>0
                       and nvl(wait_for_problem_resolve,0)=1) loop
            if Is_Track_Locked_Around(rr.id, npp_)=0  then
               if Is_Track_Locked_Around(rr.id, npp_,1)=1 then
                 errm__:='ERROR - для робота в режиме решения проблемы '||rr.id||' плохая блокировка, но можно попытаться восстановить';
                 obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                 log(rp_id__,errm__);
                 ReLock_Robot_Around(rr.id, npp_);

                 -- если команда не использует промежуточные точки
                 for nchp in (select * from command_inner where id=rr.command_inner_id and check_point is null )  loop
                   delete from track_order where robot_id=rr.id;
                 end loop;
                 -- а теперь блокировки до цели
               else
                 errm__:='ERROR - для робота '||rr.id||' плохая блокировка, восстановить нельзя, т.к. заблокировано иным роботом '||npp_;
                 obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,rr.id,errm__);
                 log(rp_id__,errm__);
               end if;
            end if;
          end loop;
        end if;
    else  -- не все роботы проставимвают
      for rr in (select * from robot where id=rid_ and nvl(command_inner_id,0)=0 and nvl(command_inner_assigned_id,0)=0 and state=0 and is_robot_lock_bad(id)=1) loop
        obj_robot.log(rid_,'    Робот стоит без команд и с плохой блокировкой, переблокируем!');
        ReLock_Robot_Around(rid_,npp_);
      end loop;

    end if;
  end if;

end;

-- линейный такт креш-теста
procedure crash_test_linear_tact is
  c1_ number;
  c2_ number;
begin
  select count(*) into c1_ from command where npp_src between 20 and 25 and npp_dest between 90 and 95 and state not in (5,2);
  select count(*) into c2_ from command where npp_dest between 20 and 25 and npp_src between 90 and 95 and state not in (5,2);
  if c1_<2 then
    for cs in (select * from cell where is_full=1 and track_npp between 20 and 25
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              order by DBMS_RANDOM.random) loop
      for cd in (select * from cell where is_full=0 and hi_level_type=1 and track_npp between 90 and 95
              and cell_size=cs.cell_size
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              order by DBMS_RANDOM.random) loop
        insert into command(cell_src_sname, cell_dest_sname)
        values(cs.sname, cd.sname);
        commit;
        return;
      end loop;
      exit;
    end loop;
  end if;

  if c2_<2 then
    for cs in (select * from cell where is_full=1 and track_npp between 90 and 95
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              order by DBMS_RANDOM.random) loop
      for cd in (select * from cell where is_full=0 and hi_level_type=1 and track_npp between 20 and 25
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              and cell_size=cs.cell_size
              order by DBMS_RANDOM.random) loop
        insert into command(cell_src_sname, cell_dest_sname)
        values(cs.sname, cd.sname);
        commit;
        return;
      end loop;
      exit;
    end loop;
  end if;


  select count(*) into c1_ from command where npp_src between 130 and 135 and npp_dest between 200 and 210 and state not in (5,2);
  select count(*) into c2_ from command where npp_dest between 130 and 135 and npp_src between 200 and 210 and state not in (5,2);
  if c1_<2 then
    for cs in (select * from cell where is_full=1 and track_npp between 130 and 135
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              order by DBMS_RANDOM.random) loop
      for cd in (select * from cell where is_full=0 and hi_level_type=1 and track_npp between 200 and 210
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              and cell_size=cs.cell_size
              order by DBMS_RANDOM.random) loop
        insert into command(cell_src_sname, cell_dest_sname)
        values(cs.sname, cd.sname);
        commit;
        return;
      end loop;
      exit;
    end loop;
  end if;

  if c2_<2 then
    for cs in (select * from cell where is_full=1 and track_npp between 200 and 210
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              order by DBMS_RANDOM.random) loop
      for cd in (select * from cell where is_full=0 and hi_level_type=1 and track_npp between 130 and 135
              and not exists (select * from cell_cmd_lock where cell_id=cell.id)
              and cell_size=cs.cell_size
              order by DBMS_RANDOM.random) loop
        insert into command(cell_src_sname, cell_dest_sname)
        values(cs.sname, cd.sname);
        commit;
        return;
      end loop;
      exit;
    end loop;
  end if;
end;

-- взять номер трека по ID ячейки
function Get_Cell_Track_Npp(cell_id_ number) return number is
begin
  for cc in (select track_npp from cell where id=cell_id_) loop
    return cc.track_npp;
  end loop;
  return null;
end;

-- посчитать сколько в треке соводных ячеек для хранения
function calc_track_free_cell(rpid_ number, track_npp_ number) return number is
  cnt_ number;
begin
  select count(*) into cnt_ from cell
  where repository_part_id=rpid_ and track_npp=track_npp_ and hi_level_type=1 and is_full=0 and not exists (select * from cell_cmd_lock  where cell_id=cell.id);
  return cnt_;
end;

-- можно ли назначить новую ячейку для выгрузки контейнера?
function is_poss_ass_new_unload_cell(old_cell_id number, robot_id_ number) return number is
 cellrec cell%rowtype;
 dir number;
begin
  try_assign_new_unload_cell(old_cell_id , robot_id_ ,cellrec, dir);
  if cellrec.id is null then
    return 0;
  else
    return 1;
  end if;
end;


-- пытаемся назначить новую ячейку выгрузки вместо старой
procedure try_assign_new_unload_cell(old_cell_id number, robot_id_ number,
            cellrec out cell%rowtype, dir out number) is
  old_cell cell%rowtype;
  cnt number;
  rpt number;
  cnpp number;
  cnpp_sorb number;
  max_npp_ number;
  delta1 number;
  delta0 number;
  sorb number;
  rp_id_ number;
  was_found number;

begin
  select * into old_cell from cell where id=old_cell_id;

  -- если ничего не нашли - Null возвращаем
  cellrec.id:=null;
  cellrec.sname:=null;
  dir:=-1;

  -- а вдруг в той же секции есть местечко
  for appr_cell in (select * from cell
                      where repository_part_id =old_cell.repository_part_id
                            and cell_size=old_cell.cell_size  and is_full=0
                            and ((hi_level_type =1 and zone_id<>0)
                                or hi_level_type =10)
                            and is_error=0
                            and service.is_cell_cmd_locked(id)=0
                            and id<>old_cell_id
                            and track_npp=old_cell.track_npp) loop
   Log(appr_cell.repository_part_id,'try_assign_new_unload_cell - нашли в текущей секции '||appr_cell.sname);
   cellrec:=appr_cell;
   dir:=1;
   return;
 end loop;

 -- раз дошли до сюда, значит нет свободного места в текущей секции
 Log(old_cell.repository_part_id,'try_assign_new_unload_cell - нет свободного места в текущей секции');
 select max_npp , spacing_of_robots,id, repository_type
 into max_npp_ , sorb, rp_id_, rpt
 from repository_part where id=(select repository_part_id from robot where id=robot_id_);
 delta1:=0; delta0:=0;
 for dir_f in 0..1  loop
   was_found:=0;
   cnpp:=old_cell.track_npp;
   cnpp_sorb:=inc_spacing_of_robots(cnpp, dir_f, sorb, rp_id_ , 0, max_npp_ );
   loop  -- цикл по направлению
     if dir_f=0 then -- против часовой
       if rpt=0 then -- линейный
         exit when cnpp=0;
       end if;
       delta0:=delta0+1;
     else -- по часовой
       if rpt=0 then -- линейный
         exit when cnpp=max_npp_;
       end if;
       delta1:=delta1+1;
     end if;
     cnpp_sorb:=inc_spacing_of_robots(cnpp_sorb, dir_f, 1, rp_id_ , 0, max_npp_ );
     cnpp     :=inc_spacing_of_robots(cnpp,      dir_f, 1, rp_id_ , 0, max_npp_ );
     select count(*) into cnt from track
     where repository_part_id=rp_id_
           and npp=cnpp_sorb
           and locked_by_robot_id in (0,robot_id_);
     if cnt>0 then -- трэк свободен
       for appr_cell in (select * from cell where repository_part_id=rp_id_
                           and track_npp=cnpp and is_full=0
                           and (cell_size<=old_cell.cell_size )
                           and ((hi_level_type =1 and zone_id<>0)
                               or hi_level_type =10)
                           and id<>old_cell_id
                           and is_error=0
                           and service.is_cell_cmd_locked(id)=0
                          order by abs(old_cell.cell_size-cell_size)) loop
         -- ура, есть ячейка
         Log(old_cell.repository_part_id,'try_assign_new_unload_cell - нашли подходящую ячейку '||appr_cell.sname||' dir='||dir_f);
         was_found:=1;
         if cellrec.id is null then -- раньше не было - пишем
           cellrec:=appr_cell;
           dir:=dir_f;
         else --уже было - на 0-вом шаге
           if delta1<delta0 and delta1<>0 and delta0<>0 then
             cellrec:=appr_cell;
             dir:=dir_f;
           end if;
         end if;
         exit;
       end loop;
       exit when was_found=1;
     else
       exit; -- дальше блокировано - вываливаемся
     end if;
   end loop; -- по направлению одному
 end loop; -- по направлениям
end;

-- назначаем новую целевую ячейки команде перемещения контейнера
procedure change_cmd_rp_goal(cmd_rp_id_ number, new_cell_dest_id number) is
  old_rp command_rp%rowtype;
begin
  select * into old_rp from command_rp where id=cmd_rp_id_;
  for cc in (select c.sname, s.track_id , t.npp, hi_level_type
             from cell c, shelving s, track t
             where c.id=new_cell_dest_id and c.shelving_id=s.id and s.track_id=t.id) loop
      update cell_cmd_lock
      set cell_id = new_cell_dest_id, sname=cc.sname
      where cell_id=old_rp.cell_dest_id and cmd_id=old_rp.command_id;
    update command_rp
    set
      cell_dest_id=new_cell_dest_id,
      cell_dest_sname =cc.sname,
      track_dest_id = cc.track_id,
      npp_dest = cc.npp
    where id=cmd_rp_id_;
    if cc.hi_level_type=1 then -- выгружаем на хранение
      for crp in (select * from command_rp where id=cmd_rp_id_) loop
        update command
        set
          cell_dest_sname=cc.sname,
          cell_dest_id=new_cell_dest_id,
          npp_dest=cc.npp,
          track_dest_id=cc.track_id
        where id=crp.command_id;
        -- а теперь command_gas правим
        for cmd in (select * from command where id=crp.command_id) loop
          update command_gas
          set cell_out_name=cc.sname
          where command_type_id in (11,18)
                and id=cmd.command_gas_id;
        end loop;
      end loop;
    else -- особые действия при выгрузке на временное хранение в транзитный склад
      for crprec in (select * from command_rp where id=cmd_rp_id_) loop
        update command_rp
        set
          cell_src_id=new_cell_dest_id,
          cell_src_sname =cc.sname,
          track_src_id = cc.track_id,
          npp_src = cc.npp
        where id<>cmd_rp_id_
          and command_id=crprec.command_id
          and rp_id=crprec.rp_id
          and state=1;
      end loop;
    end if;
  end loop;
end;

-- назначить новое место реального расположения контейнера
procedure Container_Change_Placement(BC_ varchar2,rp_id_ number,cell_id_ number) is
begin
  for cc in (select * from container where barcode=BC_) loop
    if nvl(cc.cell_id,0)=nvl(cell_id_,0) then
      raise_application_error (-20012, 'Контейнер '||BC_||' и так находится в указанной ячейке!', TRUE);
    end if;
    update cell set is_full=0, container_id=0 where id=nvl(cc.cell_id,0);
    update container set cell_id=cell_id_, location=1 where id=cc.id;
    update cell set is_full=1, container_id=cc.id where id=cell_id_;
    service.add_shelving_need_to_redraw(Get_Cell_Shelving_ID(nvl(cc.cell_id,0)));
    service.add_shelving_need_to_redraw(Get_Cell_Shelving_ID(nvl(cell_id_,0)));
    return;
  end loop;
  raise_application_error (-20012, 'Контейнер '||BC_||' не найден!', TRUE);
end;

-- получить ID стеллажа по ID ячейки
function Get_Cell_Shelving_ID(cell_id_ number) return number is
begin
  for c in (select shelving_id from cell where id=cell_id_) loop
    return c.shelving_id;
  end loop;
  return 0;
end;

-- отменяем все команды по огурцу (аккуратно!)
procedure cancel_active_cmd(rp_id_ number) is
begin
  for rp in (select * from repository_part where rp_id_=id and is_work=0) loop
    -- удаляем требования прогонов
    delete from track_order where repository_part_id=rp_id_;
    -- удаляем неначившиеся cmd_gas
    delete from command_gas where state=0 and rp_id=rp_id_;
    -- контейнеры с роботов за АСК
    for rr in (select * from robot where repository_part_id=rp_id_ and nvl(container_id,0)<>0) loop
      update container set location=0 where id=rr.container_id;
    end loop;
    delete from command_gas where state in (1,3) and rp_id=rp_id_;
    update robot set command_rp_id=0, command_inner_id=0, container_id=0, command_inner_assigned_id=0, wait_for_problem_resolve=0, platform_busy=0
    where repository_part_id=rp_id_;
    commit;
    return;
  end loop;
  raise_application_error (-20012, 'Подсклад '||rp_id_||' не найден, или он не находится в режиме паузы!', TRUE);
end;

-- простаивает ли АСК без команд?
function is_idle(rp_id_ number) return number is
begin
  for rr in (select * from robot where repository_part_id=rp_id_ and is_present=1 and
              (nvl(command_inner_id,0)<>0
               or nvl(command_inner_assigned_id,0)<>0
               or nvl(command_rp_id,0)<>0
               or nvl(wait_for_problem_resolve,0)<>0
               or state<>0
               or platform_busy<>0
              )) loop
    return 0;
  end loop;
  for tor in (select * from track_order where robot_id in (select id from robot where repository_part_id=rp_id_)) loop
    return 0;
  end loop;
  return 1;
end;

-- действия, необходимые при снятии подсклада с паузы
procedure Actione_From_Pause(rp_id_ number) is
begin
  Log(rp_id_,'Actione_From_Pause');
  if is_idle(rp_id_)=1 then
    Log(rp_id_,'АСК простаивает, его сняли с паузы, обнуляем занятость треков');
    update track set locked_by_robot_id=0
    where repository_part_id=rp_id_ and locked_by_robot_id<>0 and locked_by_robot_id not in (select id from robot where state=OBJ_ROBOT.ROBOT_STATE_REPAIR);
    commit;
  else -- не все роботы подсклада стоят
    -- обнуляем блокировки робота, на которого нет команд и который READY
    for rr in (select * from robot
               where repository_part_id=rp_id_
                     and nvl(command_inner_id,0)=0 and nvl(command_inner_assigned_id,0)=0
                     and nvl(wait_for_problem_resolve,0)=0
                     and state=OBJ_ROBOT.ROBOT_STATE_READY) loop
      Log(rp_id_,'Робот '||rr.id||' АСК простаивает, АСК сняли с паузы, обнуляем занятость треков по роботу');
      update track set locked_by_robot_id=0
      where repository_part_id=rp_id_ and locked_by_robot_id=rr.id;
      if nvl(rr.command_rp_id,0)=0 then -- и команд сверху на него нету
        Log(rp_id_,'  и команд сверху на него нету, удаляем заявки');
        delete from track_order where robot_id=rr.id;
      end if;
      commit;
    end loop;
    -- обнуляем блокировки робота, который находится в режиме решения проблемы
    for rr in (select * from robot
               where repository_part_id=rp_id_
                     and nvl(command_inner_id,0)<>0
                     and nvl(wait_for_problem_resolve,0)=1
                     and state=OBJ_ROBOT.ROBOT_STATE_READY) loop
      Log(rp_id_,'Робот '||rr.id||' АСК стоит в решении проблемы, АСК сняли с паузы, обнуляем занятость треков по роботу');
      update track set locked_by_robot_id=0
      where repository_part_id=rp_id_ and locked_by_robot_id=rr.id;
      commit;
    end loop;
  end if;
end;

-- получить имя ячейки хранения контейнера по его ШК
function get_container_cell_sname(container_barcode_ varchar2) return varchar2 is
begin
  for cc in (select cl.sname from cell cl, container cn where cn.barcode=container_barcode_ and cell_id=cl.id) loop
    return cc.sname;
  end loop;
  return null;
end;

-- акутальна ли информация в АСК по расположению роботов?
function Is_Npp_Actual_Info(rp_id_ number) return number is
begin
  for rr in (select r.*, rp.npp_actual_time  from robot r, repository_part rp
             where repository_part_id =rp.id and rp.id=rp_id_ and r.state<>OBJ_ROBOT.ROBOT_STATE_REPAIR) loop
    if sysdate-rr.last_npp_info_dt>rr.npp_actual_time then
      return 0;
    end if;
  end loop;
  return 1;
end;

-- получить максимальный приоритет активной команды по подскладу
function get_cmd_max_priority(rp_id_ number) return number is
  cnt number;
  res number;
begin
  select count(*) into cnt from command_rp
  where state in (0,1) and command_type_id=3 and rp_id =rp_id_ and date_time_begin is null;
  if cnt=0 then -- нет запущенных команд
    return 0;
  else
    select nvl(max(priority),0) into res from command_rp
    where command_type_id=3 and state in (0,1) and rp_id=rp_id_ and date_time_begin is null;
    return res;
  end if;
  return 0;

  exception when others then
    return 0;

end;

-- есть ли свободное место ?
function has_free_cell(csize in number, rp_id_ number default 0) return number is
  res number;
begin
  select count(*) into res from dual where exists
  (select * from cell
                  where
                  is_full=0 and nvl(blocked_by_ci_id,0)=0
                  and service.is_cell_over_locked(cell.id)=0
                  and nvl(is_error,0)=0
                  and hi_level_type=1 and zone_id<>0
                  and (repository_part_id=rp_id_ or nvl(rp_id_,0)=0)
                  and cell_size<=csize);
  return res;
end;

-- есть ли свободное место для контейнера заданного размера?
function has_free_cell_by_cnt(cntid in number, rp_id_ number default 0) return number is
  ct number;
begin
  select type into ct from container where id=cntid;
  return has_free_cell(ct,rp_id_);
  exception when others then
    return 0;
end;

-- получить минимальную зону хранения товара для подсклада
function get_real_min_abc_zone(rpid number) return number is
  res number;
begin
  select min(zone_id) into res
  from cell where repository_part_id=rpid and is_error=0 and hi_level_type=1 and zone_id>0;
  return res;
end;


-- посчитать расстояние до ближайшего робота от указанного трека
function calc_robot_nearest(rp_id in number, max_npp number, c_npp in number) return number is
  res number;
  t number;
  rpt number;
begin
  res:=10000;
  for rr in (select * from robot where repository_part_id=rp_id and state=0) loop
    select repository_type into rpt from repository_part where id=rr.repository_part_id;
    t:=obj_ask.calc_distance(rpt, max_npp,rr.CURRENT_TRACK_NPP, c_npp);
    if t<res then
      res:=t;
    end if;
  end loop;
  return res;
end;

-- получить ID трека по ID роботу и № трека
function get_track_id_by_robot_and_npp(robot_id_ in number, track_no in number) return number is
  ctid number;
begin
  select id into ctid
  from track
  where npp=track_no
        and repository_part_id =
            (select repository_part_id from robot where id=robot_id_);
  return ctid;
end;


-- возврашает номер участка пути увеличенное на spr секций
function inc_spacing_of_robots(npp_ in number, direction in number, spr in number, rp_id_ in number, minnppr in number default -1, maxnppr in number default -1 ) return number is
  maxnpp number;
  minnpp number;
  rpt number;
begin
  select repository_type into rpt from repository_part where id=rp_id_;
  if maxnppr<>-1 then
     maxnpp:=maxnppr;
  else
    select max(npp) into maxnpp from track where repository_part_id=RP_ID_;
  end if;
  if minnppr<>-1 then
    minnpp:=minnppr;
  else
    select min(npp) into minnpp from track where repository_part_id=RP_ID_;
  end if;
  if direction=1 then -- по часовой стрелке
    if npp_+spr<=maxnpp then
      return  npp_+spr;
    else
      if rpt=1 then  -- для кольцевого
        -- например, есть 0 1 2 3 4, мы стоим на 3, нужно увеличить на 2, 3+2-4-1
        return  npp_+spr-maxnpp-1;
      else -- для линейного при перехлесте
        return maxnpp;
      end if;
    end if;
  else -- против часовой стрелке
    if npp_-spr>=minnpp then
      return  npp_-spr;
    else
      if rpt=1 then  -- для кольцевого
        -- например, есть 0 1 2 3 4, мы стоим на 1, нужно уменьшить на 2, 1-2+4+1
        return  npp_-spr+maxnpp+1;
      else -- для линейного при самом начале
        return minnpp;
      end if;

    end if;
  end if;
end;

-- получить ID трека по огурцу и названию ячейки
function get_track_id_by_cell_and_rp(rp_id_ in number, sname_ in varchar2) return number is
  res number;
begin
  select t.id into res
  from shelving s, track t, cell c
  where
    t.id=s.track_id
    and c.sname =sname_
    and t.repository_part_id = rp_id_
    and c.shelving_id=s.id;
  return res;
end;

-- взять № трека по огурцу и названию ячейки
function get_track_npp_by_cell_and_rp(rp_id_ in number, sname_ in varchar2) return number is
  res number;
begin
  select t.npp into res
  from shelving s, track t, cell c
  where
    t.id=s.track_id
    and c.sname =sname_
    and t.repository_part_id = rp_id_
    and c.shelving_id=s.id;
  return res;
end;


-- заблокирована ли ячейка роботом в состоянии починки?
function is_cell_locked_by_repaire(cell_id_ number) return number is
  onp number;
  cnp number;
begin
  for cc in (select * from cell where id=cell_id_) loop
    for rr in (select * from robot where repository_part_id=cc.repository_part_id and state=6)  loop
      for tla in (select * from track where repository_part_id=rr.repository_part_id
                   and locked_by_robot_id =rr.id and npp=cc.track_npp) loop
        return 1;
      end loop;
      for rp in (select id, spacing_of_robots sor, max_npp
                 from repository_part where id=cc.repository_part_id) loop
        --cnp:=rr.current_track_npp;
        -- по часовой стрелке
        onp:=rr.current_track_npp;
        for dir in 0 .. 1 loop
          for delt in 1 .. rp.sor*2 loop
            cnp:=inc_spacing_of_robots(rr.current_track_npp, dir,delt, rp.id, 0, rp.max_npp);
            if cnp<>onp then -- чтоб не застряли на туда, куда нельзя пройти
              if cnp=cc.track_npp then
                return 1;
              end if;
            end if;
            onp:=cnp;
          end loop;
        end loop;
      end loop;
    end loop;
  end loop;
  return 0;
end;


-- проверка на свободность пути
function is_way_free(robot_id_ in number, npp_d number, dir number) return number is
  cnpp number;
  ll number;
  dnppsorb number;
  is_dest_npp_reached boolean;
begin
  is_dest_npp_reached:=false;
  for r in (select * from robot where id=robot_id_) loop
    log(r.repository_part_id,'is_way_free: robot_id_='||robot_id_ ||' '||npp_d ||' '|| dir);
    for rp in (select repository_type, id, max_npp, spacing_of_robots sorb, num_of_robots
               from repository_part rp where id=r.repository_part_id) loop
      if /*rp.repository_type =0 or */rp.num_of_robots=1 then -- один робот - всегда все свободно
        return 1;
      end if;
      cnpp:=r.real_npp;--r.current_track_npp;
      if cnpp=npp_d then
         return 1; -- там же и стоим
      end if;
      -- считаем максимум сколько нужно хапануть
      dnppsorb:=inc_spacing_of_robots(npp_d, dir, rp.sorb , rp.id, 0, rp.max_npp);
      log(r.repository_part_id,'dnppsorb='||dnppsorb);
      loop
        log(r.repository_part_id,'  cnpp='||cnpp);
        if cnpp=npp_d then
          is_dest_npp_reached:=true;
          log(r.repository_part_id,'    is_dest_npp_reached:=true');
        end if;
        exit when cnpp=dnppsorb and is_dest_npp_reached;
        if dir=1 then -- по часовой
           if rp.repository_type =1 then -- для кольцевого склада
             if cnpp=rp.max_npp then
                cnpp:=0;
             else
                cnpp:=cnpp+1;
             end if;
           else  -- для линейного
             if cnpp<rp.max_npp then
                cnpp:=cnpp+1;
             else
                exit; -- выход из цикла
             end if;
           end if;
        else -- против
           if rp.repository_type =1 then -- для кольцевого склада
             if cnpp=0 then
                cnpp:=rp.max_npp;
             else
                cnpp:=cnpp-1;
             end if;
           else  -- для линейного
             if cnpp>0 then
                cnpp:=cnpp-1;
             else
                exit; -- выход из цикла
             end if;
           end if;
        end if;
        dbms_output.put_line('cnpp='||cnpp);
        select locked_by_robot_id into ll from track where repository_part_id=rp.id and npp=cnpp;
        if ll<>r.id then -- ошибка
          return 0; -- путь не готов - ОШИБКА!!!
        end if;
      end loop;
    end loop;
  end loop;
  return 1; -- все проверено, мин нет
end;

-- заблокирован ли путь для робота до цели?
function is_way_locked(rp_id_ in number, robot_id_ in number, goal_npp in number) return number is
  g1 number;
  g2 number;
  cur_npp number;
  g1_is number;
  g2_is number;
  rob_rec robot%rowtype;
  sorb number;
  lbrid number;
begin
  select * into rob_rec from robot where id=robot_id_;
  select spacing_of_robots into sorb from repository_part where id=rp_id_;
  --if emu_log_level>=2 then emu_log('  is_locked: id='||r(ro_num).id||'; goal_npp='||goal_npp); end if;
  g1:=inc_spacing_of_robots(goal_npp,1,sorb,rp_id_);
  g2:=inc_spacing_of_robots(goal_npp,get_another_direction(1),sorb,rp_id_);
  --if emu_log_level>=4 then emu_log('    il: g1='||g1||'; g2='||g2); end if;

  for dir in 0..1 loop
    cur_npp:=inc_spacing_of_robots(rob_rec.current_track_npp,
                get_another_direction(dir),sorb,rp_id_);
    g1_is:=0; g2_is:=0;
    loop
      --if emu_log_level>=4 then emu_log('    il: loop cur_npp='||cur_npp); end if;
      select  locked_by_robot_id into lbrid from track
      where npp=cur_npp and repository_part_id=rp_id_;
      if lbrid<>rob_rec.id then
        exit;
      end if;
      if cur_npp=g1 then g1_is:=1; end if;
      if cur_npp=g2 then g2_is:=1; end if;
      exit when g1_is=1 and g2_is=1;
      cur_npp:=inc_npp(cur_npp,dir,rp_id_);
    end loop;
    if g1_is=1 and g2_is=1 then
      --if emu_log_level>=2 then emu_log('    il: return 1'); end if;
      return 1;
    end if;
  end loop;
  --if emu_log_level>=2 then emu_log('    il: return 0'); end if;
  return 0;
end;

-- увеличивает указанный трек на 1 по направлению
function inc_npp(cur_npp in number, dir in number, rp_id_ number) return number is
  next_npp number;
  rp_rec_min_npp number;
  rp_rec_max_npp number;
begin
  select min(npp),max(npp) into rp_rec_min_npp,rp_rec_max_npp from track where repository_part_id=rp_id_;
  if dir=1 then -- по часовой
    if cur_npp<rp_rec_max_npp then
       next_npp:= cur_npp+1;
    elsif cur_npp=rp_rec_max_npp then
       next_npp:=0;
    else
       --if emu_log_level>=1 then emu_log('  inp: Error cur_npp='||cur_npp); end if;
       null;
    end if;
  else
    if cur_npp>0 then
       next_npp:= cur_npp-1;
    elsif cur_npp=0 then
       next_npp:=rp_rec_max_npp;
    else
       --if emu_log_level>=1 then emu_log('  inp: Error cur_npp='||cur_npp); end if;
       null;
    end if;
  end if;
  return next_npp;
end;

-- разблокировать трек после ошибки команды робота
procedure unlock_track_after_cmd_error(robot_id_ in number) is
  rr robot%rowtype;
  npp1 number;
  npp2 number;
  tr_id number;
  tr_npp number;
  tr_locked_by_robot_id number;
  max_npp_ number;
  is_loop_exit number;
  sorb number;
  rpt number;
begin
  select * into rr from robot where id=robot_id_;
  select spacing_of_robots, max_npp , repository_type
  into sorb, max_npp_, rpt from repository_part where id=rr.repository_part_id;
  if rpt=0 then
    -- нет смысла замарачиваться с блокировкой на линейный склад
    return;
  end if;
  log(rr.repository_part_id,'unlock_track_after_cmf_error: robot.id='||robot_id_);
  npp1:=inc_spacing_of_robots(rr.current_track_npp, 1, sorb+1, rr.repository_part_id);
  npp2:=inc_spacing_of_robots(rr.current_track_npp, get_another_direction(1), sorb+1, rr.repository_part_id);
  --log_track(rr.repository_part_id);
  tr_npp:= npp1;
  loop
    select id, locked_by_robot_id
    into tr_id, tr_locked_by_robot_id
    from track
    where npp=tr_npp and repository_part_id=rr.repository_part_id;
    --log_ut_step(4,'  ttle: tr_npp='||tr_npp);
    if nvl(tr_locked_by_robot_id,0) in (robot_id_ ) then
      update track set locked_by_robot_id=0 where id=tr_id;
    end if;

    get_next_npp(rpt,max_npp_, tr_npp, npp2, 1,tr_npp,is_loop_exit );
    exit when is_loop_exit=1;
  end loop;
  --log_track(rr.repository_part_id);
end;


-- определяет, возможно ли заблокировать путь
function is_poss_to_lock(robot_id_ in number, track_npp_dest in number, direction_ in number,
                     crp_id_ in number default 0) return number is
  ttl_llevel integer:=0;
  track_id_dest number;
  rp_id_ number;
  tr_id number;
  tr_npp number;
  tr_locked_by_robot_id number;
  track_id_dest_pl_sor number;
  track_npp_dest_pl_sor number;
  cur_track_id number;
  track_free number;
  npp1 number;
  npp2 number;
  npp1r number;
  npp2r number;
  npplto number;
  goal_npp number;
  ret_track_id number;
  npp_ret number;
  is_in_dest number;
  cnt number;
  is_loop_exit number;
  is_poputka number;
  is_always_locked number;
  prefp varchar2(100);
  r1 robot%rowtype;
  r2 robot%rowtype;
  sorb number;
  max_npp_ number;
  rpt number;
  anroid number;
  nr number;
begin
  -- зачитываем нужные значения, инициализируем данные, пишем логи
  select * into r1 from robot where id=robot_id_;
  select t.id, rp.id , spacing_of_robots, max_npp, repository_type, num_of_robots
  into track_id_dest, rp_id_ , sorb, max_npp_, rpt, nr
  from track t, repository_part rp
  where t.npp=track_npp_dest and repository_part_id=rp.id and rp.id=r1.repository_part_id;
  if /*rpt=0 */ nr=1 then
    -- для  склада с одним роботом
    if r1.current_track_npp=track_npp_dest then
       return -1; -- уже тама
    else
       return track_id_dest;
    end if;
  end if;
  prefp:='';
  anroid:=get_another_robot_id(robot_id_);
  select * into r2 from robot where id=anroid;
  is_in_dest:=0;
  cur_track_id:=r1.current_track_id;
  if track_id_dest=cur_track_id then
      return 1;
  end if;

  npp1:=r1.current_track_npp;
  npp1r:=inc_spacing_of_robots(npp1,direction_,sorb,rp_id_); -- убрали +1
  npp2:=track_npp_dest;
  npp2r:=inc_spacing_of_robots(npp2,direction_,sorb,rp_id_);

  track_id_dest_pl_sor:=get_track_id_by_robot_and_npp(robot_id_,npp2r);
  track_npp_dest_pl_sor:=npp2r;

  tr_npp:=npp1r;
  loop
    tr_id:=get_track_id_by_robot_and_npp(robot_id_,tr_npp);
    select  locked_by_robot_id into tr_locked_by_robot_id from track where id=tr_id;

    if nvl(tr_locked_by_robot_id,0)=0 then
      --update track set locked_by_robot_id=r1.id where id=tr_id;
      ret_track_id:=tr_id;
      npp_ret:=tr_npp;

    -- заблокировано кем то иным
    elsif nvl(tr_locked_by_robot_id,0)<>r1.id then
      return 0;

    else -- этим же роботом и заблокировано
      ret_track_id:=tr_id;
      npp_ret:=tr_npp;
    end if;
    get_next_npp(rpt, max_npp_,tr_npp, npp2r, direction_,tr_npp,is_loop_exit);
    exit when is_loop_exit=1;
  end loop;

  if ret_track_id=track_id_dest_pl_sor then
     -- добрались до конечного трэка с учетом расстояния между роботами
     return 1;
  else -- не дошли до конечного трэка
     return 0;
  end if;
end;

-- получить id второго робота
function get_another_robot_id(r_id_ in number) return number is
  res number;
begin
  begin
  select id into res from robot where id<>r_id_ and repository_part_id=
      (select repository_part_id from robot where id=r_id_);
  return res;
  exception when others then
    return 0;
  end;
end;

-- взять № трека по его ID
function get_track_npp_by_id(id_ in number) return number is
  npp_ number;
begin
  select npp into npp_ from track where id=id_;
  return npp_;
end;

-- указанный трек между двумя треками по направлению?
function is_track_between(goal_npp in number,npp_from in number,npp_to in number,dir in number, rp_id_ in number) return number is
  rp_rec_max_npp number;
  rp_rec_min_npp number;
begin
  select min(npp),max(npp) into rp_rec_min_npp,rp_rec_max_npp from track where repository_part_id=rp_id_;
  if dir=1 then
    -- по часовой стрелке
    for i in npp_from..rp_rec_max_npp loop
      if i=goal_npp then
        return 1;
      end if;
      if i=npp_to then
        return 0;
      end if;
    end loop;
    -- за конец
    for i in rp_rec_min_npp..npp_to loop
      if i=goal_npp then
        return 1;
      end if;
      if i=npp_to then
        return 0;
      end if;
    end loop;
  else
    -- против часовой стрелке
    for i in REVERSE rp_rec_min_npp..npp_from loop
      if i=goal_npp then
        return 1;
      end if;
      if i=npp_to then
        return 0;
      end if;
    end loop;
    -- за конец
    for i in REVERSE npp_to..rp_rec_max_npp loop
      if i=goal_npp then
        return 1;
      end if;
      if i=npp_to then
        return 0;
      end if;
    end loop;
  end if;
  return 0;
end;

-- получить ID трека по названию ячейка и ID робота
function get_track_id_by_cell_and_robot(sname_ in varchar2, robot_id_ in number) return number is
  rp_id_  number;
  res number;
begin
  select repository_part_id into rp_id_ from robot r where r.id=robot_id_;
  select t.id into res
  from shelving s, track t, cell c
  where
    t.id=s.track_id
    and c.sname =sname_
    and t.repository_part_id = rp_id_
    and c.shelving_id=s.id;
  return res;
end;


end obj_rpart;
/
