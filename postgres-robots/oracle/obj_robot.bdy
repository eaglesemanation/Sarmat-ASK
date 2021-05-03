create or replace package body obj_robot is -- тело пакета объекта "Робот"

-- получить имя файла лога
function Get_Log_File_Name(robot_id_ in number) return varchar2 is
begin
  return 'robot_ora_'||robot_id_||'_'||to_char(sysdate,'ddmmyy')||'.log';
end;

-- формируем строку ошибки робота в заивиммости от кода ошибки
function Get_Error_Msg_By_Code(error_code in number) return varchar2 is
  erm varchar2(3000);
begin
       erm:='';
       for err in (select * from cmd_error_code order by code) loop
         if bitand(error_code,err.code) <>0 then
           if erm is null then
              erm:=err.descr;
           elsif length(erm)+length(err.descr)<250 then
              erm:=err.descr||', '||err.descr;
           else
              erm:=substr(err.descr||', '||err.descr,0,250);
           end if;
         end if;
       end loop;
       return erm;

end;

-- запись строки в лог
procedure Log(robot_id_ number, txt_ varchar2) is
 file_handle__  utl_file.file_type;
 fn__ varchar2(300);
begin
 fn__:=Get_Log_File_Name(robot_id_);
 file_handle__ := sys.utl_file.fopen('LOG_DIR', fn__, 'A');
 utl_file.put_line(file_handle__, to_char(systimestamp,'hh24:mi:ss.ff')||' '||txt_);
 utl_file.fclose(file_handle__);
end;

-- получить подсклад робота по его ID
function Get_Robot_RP_ID(rid_ number) return number is
begin
  for rr in (select * from robot where id=rid_) loop
    return rr.repository_part_id;
  end loop;
  return -1;
end;

-- получить имя подсклада робота по ID робота
function Get_Robot_RP_name(rid_ number) return varchar2 is
begin
  for rr in (select rp.name from robot r, repository_part rp where r.id=rid_ and repository_part_id=rp.id) loop
    return rr.name;
  end loop;
  return '';
end;


-- получить состояние робота по его ID
function Get_Robot_State(rid_ number) return number is
begin
  for rr in (select * from robot where id=rid_) loop
    return rr.state;
  end loop;
  return null;
end;

-- получить имя робота по его ID для отчета
function Get_Robot_Name(rid_ number) return varchar2 is
begin
  for rr in (select r.name, r.port, rp.name rpname from robot r, repository_part rp
             where r.id=rid_ and repository_part_id=rp.id) loop
    return rr.rpname||':'||rr.name||':'||rr.port;
  end loop;
  return '';
end;


-- помечаем текущую простую команду робота как ошибочную
procedure Cur_Cmd_Inner_Fault(rid_ number) is
  msg_ varchar2(4000);
begin
  Log(rid_,'Ставим текущую команда робота как ошибочную');
  for rr in (select * from robot where id=rid_) loop
    if nvl(rr.command_inner_id,0)=0 then
      msg_:='ERROR - CurCmdInnerFault, а на роботе нет команд';
      obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
      Log(rid_,msg_);
    else
      update command_inner set state=2 where id=rr.command_inner_id;
      update robot
      set
        command_inner_id=null
      where id=rid_;
      commit;
    end if;
  end loop;

end;

-- Переключаем робота в режим решение проблемы
procedure To_Problem_Resolve_Mode(rid_ number, errm_ varchar2 default '') is
begin
  Log(rid_,'Переключаем робота в режим решение проблемы');
  update robot
  set
    WAIT_FOR_PROBLEM_RESOLVE=1,
    cmd_error_descr=errm_
    --command_inner_id=null
  where id=rid_;
  commit;
end;


-- решение с компьютера оператора  простое
function Problem_Resolve(comp_name_ varchar2) return number is
  ci_id_ number;
  pr_ number;
begin
  ci_id_:=get_last_comp_ci(comp_name_);
  dbms_output.put_line('ci_id_='||ci_id_);
  if ci_id_>0 then
    for cc in (select ci.*, r.platform_busy
               from command_inner ci, robot r
               where ci.id=ci_id_ and ci.state not in (2,5) and r.id=ci.robot_id
               order by ci.id desc) loop
      select nvl(id,0) into pr_ from problem_resolving where command_type_id=cc.command_type_id and (nvl(platform_busy,0)=nvl(cc.platform_busy,0) or platform_busy is null);
      return Problem_Resolve(cc.robot_id, cc.command_type_id, cc.platform_busy, pr_);
    end loop;
  end if;
  return 0;
end;

-- решение проблемы команды сложное, с параметрами
function Problem_Resolve(rid_ number, cit_ number, pb_ number, pr_id_ number, ans_ varchar2 default '') return number is
  msg_ varchar2(4000);
begin
  msg_:='Пришло решение проблемы робот '||rid_||' cit_='||cit_ ||' pb_='|| pb_||' ID решения='||pr_id_||' ans='||ans_;
  dbms_output.put_line(msg_);
  Log(rid_, msg_);
  for rr in (select ci.id, ci.command_type_id, r.platform_busy, r.WAIT_FOR_PROBLEM_RESOLVE
             from robot r, command_inner ci
             where r.id=rid_ and command_inner_id=ci.id) loop
    if nvl(rr.WAIT_FOR_PROBLEM_RESOLVE,0)<>1 then
      msg_:='ERROR - проблема уже решена!';
      obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
      Log(rid_,msg_);
      return 0;
    end if;
    msg_:='Определена команда, что решать проблему  '||rr.id;
    dbms_output.put_line(msg_);
    Log(rid_, msg_);
    if rr.command_type_id<>cit_ or rr.platform_busy<>pb_ then
      msg_:='ERROR - по мере решения проблемы сменилась ситуация '||cit_ ||' '|| pb_||' '||rr.command_type_id||' '||rr.platform_busy;
      obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
      Log(rid_,msg_);
      return 0;
    else
      for pr in (select * from problem_resolving pr
                 where command_type_id=cit_ and pb_=nvl(pr.platform_busy,pb_) and id=pr_id_) loop
        begin
          dbms_output.put_line('update command_inner  set problem_resolving_id='||pr.id||' where id='||rr.id);
          update command_inner
          set problem_resolving_id=pr.id, problem_resolving_par=ans_
          where id=rr.id;
          commit;
          return 1;
        exception when others then
          msg_:='ERROR - ошибка решения проблемы '||SQLERRM;
          dbms_output.put_line(msg_);
          rollback;
          obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
          Log(rid_,msg_);
          raise_application_error (-20003, msg_, TRUE);
          return 0;
        end;
      end loop;
    end if;
  end loop;
  -- раз дошли сюда, то значит, что команды не было, проверяем и делаем
  for rr in (select *
             from robot r
             where r.id=rid_ and nvl(command_inner_id,0)=0) loop
    Log(rid_,'  проблема выполнения команды есть, а самой команды нет, убираем нафиг состояние решения проблемы ');
    if nvl(rr.WAIT_FOR_PROBLEM_RESOLVE,0)<>1 then
      msg_:='ERROR - проблема уже решена!';
      obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
      Log(rid_,msg_);
      return 0;
    else
      update robot set WAIT_FOR_PROBLEM_RESOLVE=0 where id=rid_ and nvl(WAIT_FOR_PROBLEM_RESOLVE,0)=1;
      commit;
      return 1;
    end if;
  end loop;
  -- проблема команды есть, а самой команды нет, переводим в режим что все ок - возможно, сисадмин напутал
  msg_:='ERROR - проблема команды есть, а самой команды нет, переводим в режим что все ок - возможно, сисадмин напутал';
  obj_ask.global_error_log(obj_ask.error_type_robot,null,rid_,msg_);
  Log(rid_,msg_);
  update robot set WAIT_FOR_PROBLEM_RESOLVE=0 where id=rid_ and nvl(WAIT_FOR_PROBLEM_RESOLVE,0)=1;
  commit;

  return 0;
end;

-- отчет по завершению реальной команды робота (а не INFO)
procedure Real_Cmd_Report(robot_id_ in number, command_inner_id_ in number,
                         command_answer_ in varchar2, error_code_ in number default Null,
                         plat_stat_ in varchar2 default '') is
  rp number;
  rpt number;
  erm__ varchar2(500);
  ctid number;
  cirec command_inner%rowtype;
  r_ci_type number;
  rps repository%rowtype;
  cellrec cell%rowtype;
  robrec robot%rowtype;
  command_inner_id__ number;
  cnt number;
  ci_found number;
  htp number;
  direction_ number;
  is_unkn_cmd boolean;
  lct number;
begin
  Log(robot_id_,'Отчёт по выполнению реальной команды '||command_inner_id_||' ответ '||command_answer_||' ошибка='||error_code_);
  command_inner_id__:=command_inner_id_;
  select repository_part_id into rp from robot where id=robot_id_;
  select * into rps from repository;
  select * into robrec from robot where id=robot_id_;
  log(robot_id_,erm__);

  r_ci_type:=-1;
  if nvl(robrec.command_inner_id,0)<>0 then
    select command_type_id into r_ci_type from command_inner where id=robrec.command_inner_id;
    begin
      -- взяли тип команды, назначенной на робота
      select nvl(command_type_id,0) into lct from command_inner where id=nvl(robrec.command_inner_id,0);
    exception when others then
      lct:=0;
    end;
    log(robot_id_,'  lct='||lct);
  end if;

  select count(*) into ci_found from command_inner where id=nvl(command_inner_id_,0);
  if ci_found=0 or lct=32 then -- не найдено команды, что робот возвратил
    is_unkn_cmd:=true;
    erm__:='ERROR - нет команды с id='||command_inner_id_;
    obj_ask.global_error_log(obj_ask.error_type_robot,null,robot_id_,erm__);
    if /*nvl(command_inner_id_,0)=0 and*/ lct=32 then -- INITY - возвращает 0 - это фича агента на команду эту
      log(robot_id_,'  все же INITY');
      is_unkn_cmd:=false;
      select * into cirec from command_inner where id=robrec.command_inner_id;
      command_inner_id__:=robrec.command_inner_id;
    --elsif  then
    elsif robrec.WAIT_FOR_PROBLEM_RESOLVE=0 then -- по ходу команда реальная
      log(robot_id_,'  команда не найдена, и она не INITY');
      To_Problem_Resolve_Mode(robot_id_);
      return;
    end if;
  else -- команда, которую прислал робот, есть в списке команд
     is_unkn_cmd:=false;
     if r_ci_type=32 then
       if robrec.command_inner_id<>command_inner_id__ then
         command_inner_id__:=robrec.command_inner_id;
       end if;
     end if;
     select * into cirec from command_inner where id=command_inner_id__;
  end if;


  -- Если возвращенное состояние "SUCCESS", то
  if (instr(command_answer_,'SUCCESS')<>0 and not is_unkn_cmd) or lct=32 then
       Log(robot_id_,'  пришел SUCCESS или был Inity');
       if cirec.date_time_begin is null then
         erm__:='  ERROR - дата-время начала команды NULL';
         obj_ask.global_error_log(obj_ask.error_type_robot,null,robot_id_,erm__);
         Log(robot_id_,erm__);
         return;
       end if;
       if sysdate-cirec.date_time_begin<(1/(24*60*10))  then
         Log(robot_id_,'  слишком малое время с начала выполнения команды');
         return;
       end if;
       for rr in (select * from robot where id=robot_id_) loop
         if rr.command_inner_id<>nvl(command_inner_id__,0) then -- возвращено ID назначенной команды
           Log(robot_id_,'  ERROR - ID пришедшей команды '||command_inner_id__||', а ID команды на роботе '||rr.command_inner_id);
           -- проверяем, а не мало ли времени прошло с момента выдачи последней команды на робота
           if (sysdate-nvl(get_cmd_inner_dtb(rr.command_inner_id),sysdate-1))<(1/(24*60*10))  then
             Log(robot_id_,'  мало времени прошло с момента выдачи последней команды на робота');
             return;
           end if;
           To_Problem_Resolve_Mode(robot_id_);
           return;
         end if;
         -- проверка на целевой трек
         -- проверяем, не INITY ли команда?
         if (r_ci_type<>32) and (rr.current_track_npp<>Get_Cmd_Inner_Npp_Dest(cirec.id)) then
           Log(robot_id_,'  не равен целевой трек команды и текущий трек робота');
           To_Problem_Resolve_Mode(robot_id_);
           return;
         end if;
       end loop;
       for ci in (select * from command_inner where id=command_inner_id__ and state<>5) loop
         if ci.command_type_id=CMD_LOAD_TYPE_ID then
           if robrec.platform_busy<>1 then
             Log(robot_id_,'  ERROR - LOAD завершен, а платформа пустая');
             To_Problem_Resolve_Mode(robot_id_);
             return;
           end if;
         elsif ci.command_type_id=CMD_UNLOAD_TYPE_ID then
           if robrec.platform_busy<>0 then
             Log(robot_id_,'  ERROR - UNLOAD завершен, а платформа полная');
             To_Problem_Resolve_Mode(robot_id_);
             return;
           end if;
         end if;
       end loop;
       update command_inner
       set state=5, date_time_end=sysdate
       where id=command_inner_id__ and state<>5;
       if SQL%ROWCOUNT>0 then
          Log(robot_id_,'Сменили state команды '||command_inner_id__||' на 5');
       end if;
       -- сбрасываем ожидание решение проблемы, если ситуация вдруг поменялась
       update robot set wait_for_problem_resolve=0
       where command_inner_id_=nvl(command_inner_id,0) and id=robot_id_ and nvl(wait_for_problem_resolve,0)=1;
       update robot
       set command_inner_id=Null, cmd_error_descr=''
       where id=robot_id_ and command_inner_id is not null;
       if SQL%ROWCOUNT>0 then
          Log(robot_id_,'Сменили command_inner_id на Null');
       end if;
       commit;

  elsif instr(command_answer_,'CMD_FAULT')<>0 or instr(command_answer_,'CMD_NONE')<>0  or is_unkn_cmd then
     log(robot_id_,'Пришла ошибка команды '||command_inner_id_||' № '||error_code_||':'||command_answer_||' на команде '||cirec.command_to_run);
     if nvl(error_code_,0)<>0 then
       update command_inner set error_code_id =error_code_ where id=command_inner_id_;
     end if;
     if nvl(error_code_,0)<>0 then
       erm__:=get_error_msg_by_code(error_code_);
     else
       erm__:='';
     end if;
     To_Problem_Resolve_Mode(robot_id_, erm__);

  -- Если возвращенное состояние "WORK" или "WAIT", то странная ошибка робота - INFO возвращает что робот готов, а команда на нем еще не выполнилась. что делаем
  elsif instr(command_answer_,'WORK')<>0 or
        instr(command_answer_,'PAUSE')<>0 or
        instr(command_answer_,'WAIT')<>0 then
     update robot
     set state=1
     where id=robot_id_ and state<1;
     if SQL%ROWCOUNT>0 then
        Log(robot_id_,'Сменили state у робота на 1');
     end if;
     commit;

  -- Если UNKNOWN при реально ранее посланной команде
  elsif instr(command_answer_,'UNKNOWN')<>0  and not is_unkn_cmd then
     To_Problem_Resolve_Mode(robot_id_);
     return;
  end if;

end;

-- даем команду роботу INITY, если нужно
procedure InitY_If_Ness(rid_ number) is
  ci_id number;
  cnt number;
  ciy_id number;
begin
  for rr in (select * from robot r
             where id=rid_ and nvl(inity_freq,0)>0
                   and Is_Robot_Ready_For_Cmd(r.id)=1) loop
    select nvl(max(id),0) into ci_id from command_inner where robot_id=rr.id and command_type_id<>32;
    if ci_id<>0 then
      select state into cnt from command_inner where id=ci_id;
      if cnt<>5 then
        CONTINUE;
      end if;
    end if;
    select nvl(max(id),0) into ciy_id from command_inner where robot_id=rr.id and command_type_id=32 and state in (5,3);
    cnt:=0;
    if ciy_id>0 then
      select count(*) into cnt from command_inner where robot_id=rr.id and command_type_id<>32 and state=5 and id>ciy_id;
    end if;
    if ciy_id=0 or cnt>rr.inity_freq then
      log(rid_,'');
      log(rid_,'************************************************* ');
      log(rid_,'суем inity ');
      Set_Command_Inner(rr.id, 0, 3, 32, 0, obj_rpart.get_cell_name_by_track_id(rr.current_track_id),
                  obj_rpart.get_cell_name_by_track_id(rr.current_track_id),'INITY;');
    end if;

  end loop;

end;

-- корректируем ID команды, если вернутое есть ID промежуточной точки. Заодно помечаем кмд промежут как переданную
function correct_ci_id_on_checkpoint(CMDID_ number) return number is
begin
  for ci in (select * from command_inner where id=CMDID_) loop
    return CMDID_; -- есть такая команда, ее и возвращаем
  end loop;
  for chp in (select * from command_inner_checkpoint where gv_ci_id=CMDID_) loop
    if chp.date_time_acc_robot is null then -- еще не помечена как принятая роботом к исполнению
      Mark_CI_CP_Send_To_Robot(CMDID_,3);
    end if;
    return chp.command_inner_id;
  end loop;
  return CMDID_;
end;

-- доклад SQL серверу о состоянии робота с Sarmat
procedure Info_From_Sarmat(rid_ number, rez_ in varchar2) is
  ncmt__ boolean;
  robot_state__ varchar2(200);
  CMDID__ number;
  CMDANS__  varchar2(200);
  CMD_ERR_CODE__ number;
  LogPrefixWas boolean default false;
  ttl__ number;
  errm__ varchar2(1000);
  v_array sys.odcivarchar2list; --apex_application_global.vc_arr2;
  new_track_id__ number;
  new_track_npp__ number;
  rp_id__ number;
  nor__ number;
  new_dir_ number;
  uchp number;

  procedure ilog(txt_ varchar2) is
  begin
    if not LogPrefixWas then
      Log(rid_,'');
      Log(rid_,'****************** пришло INFO по роботу '||rez_);
      LogPrefixWas:=true;
    end if;
    Log(rid_,txt_);
  end;

begin
  ncmt__:=false;
  ilog('Начало цикла INFO');

  if rez_ is null then -- нет связи
    update robot set state=8 where id=rid_ and state<>8;
    if SQL%ROWCOUNT>0 then
      ilog('Смена состояния робота в [Нет связи]');
    end if;
    commit;
    return;
  end if;

  rp_id__:=Get_Robot_RP_ID(rid_);
  nor__:=obj_rpart.Get_RP_Num_Of_robots(rp_id__);
  select is_use_checkpoint into uchp from robot where id=rid_;

  -- разбираем ответ от робота INFO
  v_array := extend.parse_csv_string(rez_);--apex_util.string_to_table(rez_, ';');

   -- считываем ID команды
   if v_array(19) is not null then
     CMDID__:=service.to_number_my(v_array(19));
   else
     CMDID__:=null;
   end if;

  if CMDID__ is not null and uchp=1 then
    CMDID__:=correct_ci_id_on_checkpoint(CMDID__); -- корректируем ID команды, если вернутое есть ID промежуточной точки. Заодно помечаем кмд промежут как переданную
  end if;

  -- не было ли перегруза агента?
  if nvl(CMDID__,0)<=0 then
    for rr in (select * from robot
               where id=rid_ and nvl(command_inner_id,0)<>0 ) loop -- команда прошла, и связь порвалась
      if nvl(rr.wait_for_problem_resolve,0)=0 then
        errm__:='  ERROR for robot='||rid_ ||' команда значится, а агент пустоту возвращает';
        obj_ask.global_error_log(obj_ask.error_type_robot,rr.repository_part_id,rr.id,errm__);
        ilog(errm__);
      end if;
    end loop;
  end if;

  for rr in (select * from robot
             where id=rid_ and nvl(command_inner_id,0)=0 and nvl(command_inner_assigned_id,0)<>0
                   and nvl(command_inner_assigned_id,0)=nvl(CMDID__,0)) -- команда прошла, и связь порвалась
  loop
    ilog('Прервалась связь на посылке команды, помечаем, что команда прошла ок!');
    Mark_Cmd_Inner_Send_To_Robot(rid_,CMDID__);
  end loop;


   -- состояние
    robot_state__:=v_array(3);
    if instr(robot_state__,'ERROR')>0 then
      update robot set state=2 where id=rid_ and state<>2;
      if SQL%ROWCOUNT>0 then
        ilog('Смена состояния робота на 2');
        ncmt__:=true;
      end if;
      commit;
      return; -- выходим, т.к. ничего неясно
    end if;

    if instr(robot_state__,'READY')>0 then
      update robot set state=0 where id=rid_ and state<>0;
      if SQL%ROWCOUNT>0 then
        ilog('Смена состояния робота на 0');
        ncmt__:=true;
      end if;
      commit;
    end if;

    -- проверка на корректность нового трека
    new_track_npp__:=obj_rpart.get_track_npp_by_npp(v_array(2),Get_Robot_RP_ID(rid_));
    if nor__>1 then
      obj_rpart.Check_New_Robot_Npp_Correct(rid_,new_track_npp__);
    end if;

    update robot
    set
      real_npp= new_track_npp__
    where id=rid_ and nvl(real_npp,-1)<>new_track_npp__;
    if SQL%ROWCOUNT>0 then
      ilog('Смена текущего реального трека на '||new_track_npp__);
      ncmt__:=true;
    end if;
    -- ниже нужно будет переделать, чтою смотреть, можно ли проставлять трек такой
    new_track_id__:=obj_rpart.get_track_id_by_npp(new_track_npp__,Get_Robot_RP_ID(rid_));
    update robot
    set
      --current_track_npp=v_array(2), -- само в триггере определяется
      current_track_id=new_track_id__
    where id=rid_ and current_track_id<>new_track_id__;
    if SQL%ROWCOUNT>0 then
      ilog('Смена текущего трек ID на '||new_track_id__||' (npp пришел '||v_array(2)||')');
      ncmt__:=true;
      select current_track_npp into new_track_npp__ from robot where id=rid_;
      ilog('  новый трек NPP триггерно выставился '||new_track_npp__);
      if obj_rpart.Check_Lock_Robot_Around(rid_, new_track_npp__)<>1 then
        errm__:='ERROR - не получается заблокировать вокруг робота в секции '||v_array(2);
        ilog(errm__);
        raise_application_error (-20012, errm__, TRUE);
      end if;
    end if;
 -- платформа
    if v_array(6)='FREE' then
      update robot set platform_busy=0 where id=rid_ and platform_busy<>0;
      if SQL%ROWCOUNT>0 then
        ilog('Смена занятости платформы на 0');
        ncmt__:=true;
      end if;
    elsif v_array(6)='BUSY' then
      update robot set platform_busy=1 where id=rid_ and platform_busy<>1;
      if SQL%ROWCOUNT>0 then
        ilog('Смена занятости платформы на 1');
        ncmt__:=true;
      end if;
    end if;
 -- направление
   if v_array(17) is not null then
     if v_array(17)='CCW' then
       new_dir_:=DIR_CCW;
     elsif v_array(17)='CW' then
       new_dir_:=DIR_CW;
     else
       new_dir_:=DIR_NONE;
     end if;
   else
     new_dir_:=DIR_CW;
   end if;
   update robot set direction=new_dir_ where id=rid_ and direction<>new_dir_;
   if SQL%ROWCOUNT>0 then
     ilog('Смена направления движения робота на '||new_dir_);
     ncmt__:=true;
   end if;
   CMD_ERR_CODE__:=service.to_number_my(v_array(21));
   CMDANS__:=v_array(20);


  -- разобрали ответ
  if instr(robot_state__,'READY')>0 then
    for rr in (select * from robot
               where id=rid_
                     and nvl(command_inner_id,0)<>0
                     and nvl(wait_for_problem_resolve,0)=0) loop
        ilog('Робот свободен, и на нём числится команда, разбираемся в ситуации');
        Real_Cmd_Report(rid_ , CMDID__, CMDANS__, CMD_ERR_CODE__);
    end loop;
  end if;

  if instr(robot_state__,'WORK')>0 then
    update robot set state=1 where id=rid_ and state<>1;
    if SQL%ROWCOUNT>0 then
      ilog('Смена состояния робота на 1');
      ncmt__:=true;
    end if;
  end if;

  if instr(robot_state__,'INITIALIZATION')>0 then
    update robot set state=3 where id=rid_ and state<>3;
    if SQL%ROWCOUNT>0 then
      ilog('Смена состояния робота на 3');
      ncmt__:=true;
    end if;
  end if;

  if instr(robot_state__,'INITIALIZATION')>0 or instr(robot_state__,'WORK')>0 or instr(robot_state__,'READY')>0 then -- ответ робота о треке корректен
    update robot set last_npp_info_dt =sysdate where id=rid_;
    ncmt__:=true;
  end if;

  if ncmt__ then
    commit;
  end if;

  ilog('Завершение такта цикла INFO');

end;


-- отмечаем, что команда успешно отдана роботу на исполнение
procedure Mark_Cmd_Inner_Send_To_Robot(robot_id_ in number, cmd_inner_id_ in number) is
begin
  Log(robot_id_,'Пришло сообщение об успешной назначении команды '||cmd_inner_id_||' на робота');
  update command_inner c set c.state = 3 where c.id = cmd_inner_id_;
  update robot set command_inner_id= cmd_inner_id_ where id=robot_id_;
  commit;
  Log(robot_id_,'Команда '||cmd_inner_id_||' успешно назначена на робота');
end;

-- выдаем роботу простую команду типа load/Unload/Move
procedure Set_Command_Inner(robot_id_ in number,
                      crp_id_ in number,
                      new_cmd_state_ in number,
                      cmd_inner_type_ in number,
                      dir_ in number,
                      cell_src_sname_ in varchar2,
                      cell_dest_sname_ in varchar2,
                      cmd_text_ in varchar2,
                      container_id_ in number default 0,
                      check_point_ number default null) is
  rob_rec__ robot%rowtype;
  ciid__ number;
  cnt__ number;
  ci_rec__ command_inner%rowtype;
  errmm__ varchar2(4000);
  lpfix__ varchar2(40);
  rp_id__ number;
  nomr__ number;
  npp_rd__ number;
begin
  select * into rob_rec__ from robot where id=robot_id_;
  rp_id__:=rob_rec__.repository_part_id;
  select num_of_robots into nomr__ from repository_part where id=rp_id__;


  log(robot_id_,'set_command_inner: robot_id_='||robot_id_ ||
                    '; crp_id_='||crp_id_||
                    '; new_cmd_state='||new_cmd_state_||
                    '; cmd_inner_type='||cmd_inner_type_||
                    '; dir='||dir_||
                    '; cell_src_sname_='||cell_src_sname_||
                    '; cell_dest_sname_='||cell_dest_sname_||
                    '; cmd_text='||cmd_text_);
  select count(*) into cnt__ from command_inner
  where robot_id=robot_id_ and state=3;
  if cnt__<>0 then
    errmm__:='ERROR постановки команды - назначается новая, а есть еще старая ';
    log(robot_id_, errmm__);
    raise_application_error (-20003, errmm__, TRUE);
  end if;
  if rob_rec__.state<>0 then
    errmm__:='ERROR постановки команды для робота '||robot_id_||' - робот занят!';
    log(robot_id_, errmm__);
    raise_application_error (-20012, errmm__, TRUE);
  end if;
  if nvl(rob_rec__.command_inner_assigned_id,0)<>0 then
    errmm__:='ERROR постановки команды для робота '||robot_id_||' - уже закреплена но не запущена команда '||rob_rec__.command_inner_assigned_id;
    log(robot_id_, errmm__);
    raise_application_error (-20012, errmm__, TRUE);
  end if;
  if cell_src_sname_ is null and cell_dest_sname_ is null then
    errmm__:='ERROR постановки команды для робота '||robot_id_||' - пустые и источник и приемник!';
    log(robot_id_, errmm__);
    raise_application_error (-20012, errmm__, TRUE);
  end if;

  rob_rec__.state:=1;
  ci_rec__.command_type_id:=cmd_inner_type_;
  ci_rec__.direction:=dir_;
  if cell_src_sname_ is not null then
    select c.id, t.npp, t.id
    into ci_rec__.cell_src_id, ci_rec__.npp_src, ci_rec__.track_src_id
    from cell c, shelving s, track t
    where c.sname=cell_src_sname_ and c.shelving_id=s.id and s.track_id=t.id and t.repository_part_id=rob_rec__.repository_part_id;
  else
    ci_rec__.cell_src_id:=0;
    ci_rec__.npp_src:=0;
    ci_rec__.track_src_id:=0;
  end if;
  if cell_dest_sname_ is not null then
    select c.id, t.npp, t.id
    into ci_rec__.cell_dest_id, ci_rec__.npp_dest, ci_rec__.track_dest_id
    from cell c, shelving s, track t
    where c.sname=cell_dest_sname_ and c.shelving_id=s.id and s.track_id=t.id and t.repository_part_id=rob_rec__.repository_part_id;
  else
    ci_rec__.cell_dest_id:=0;
    ci_rec__.npp_dest:=0;
    ci_rec__.track_dest_id:=0;
  end if;

  -- проверка на занятость плафтормы
  if cmd_inner_type_ in (5) then -- unload
    if rob_rec__.platform_busy=0 then
      update robot set wait_for_problem_resolve=1 where id=robot_id_;
      errmm__:='  ERROR for robot='||robot_id_ ||' rob_rec.platform_busy=0';
      obj_ask.global_error_log(obj_ask.error_type_robot,rp_id__,robot_id_,errmm__);
      log(robot_id_,errmm__);
      return;
      --raise_application_error (-20012, 'Неовзможно дать команду unload при пустой плафторме');
    end if;
  elsif cmd_inner_type_ in (4) then -- load
    if rob_rec__.platform_busy=1 then
      update robot set wait_for_problem_resolve=1 where id=robot_id_;
      errmm__:='  ERROR for robot='||robot_id_ ||' rob_rec.platform_busy=1';
      obj_ask.global_error_log(obj_ask.error_type_robot,rp_id__,robot_id_,errmm__);
      log(robot_id_,errmm__);
      return;
    end if;
  end if;

  if nomr__>1 then -- проверяем, а заблокирован ли трек до цели в случае > 1-го робота
    if  cmd_inner_type_ in (5,6) then
      npp_rd__ :=ci_rec__.npp_dest;
    else
      npp_rd__ :=ci_rec__.npp_src;
    end if;
    if check_point_ is not null then
      npp_rd__ :=check_point_;
    end if;
    if obj_rpart.is_track_locked(robot_id_, npp_rd__, dir_)=0 then
      errmm__:='ERROR - Ошибка постановки команды для робота '||robot_id_||' - команды '||cmd_text_||' - незаблокирован трек до секции '||npp_rd__||'!';
      obj_ask.global_error_log(obj_ask.error_type_robot_rp,rp_id__,robot_id_,errmm__);
      log(robot_id_, errmm__);
      raise_application_error (-20012, errmm__, TRUE);
    end if;
  end if;

  -- проверка для LOAD/UNLOAD
  if service.is_cell_full_check=1 then
    if cmd_inner_type_=CMD_LOAD_TYPE_ID then
      for cc in (select * from cell where id=ci_rec__.cell_src_id and is_full=0) loop
        errmm__:='ERROR - Ошибка постановки команды для робота '||robot_id_||' - команды '||cmd_text_||' - ячейка - источник для LOAD пуста!';
        obj_ask.global_error_log(obj_ask.error_type_robot,rp_id__,robot_id_,errmm__);
        log(robot_id_, errmm__);
        raise_application_error (-20012, errmm__, TRUE);
      end loop;
    elsif cmd_inner_type_=CMD_UNLOAD_TYPE_ID then
      for cc in (select * from cell where id=ci_rec__.cell_dest_id and is_full>=max_full_size) loop
        errmm__:='ERROR - Ошибка постановки команды для робота '||robot_id_||' - команды '||cmd_text_||' - ячейка - приемник для UNLOAD переполнена!';
        obj_ask.global_error_log(obj_ask.error_type_robot,rp_id__,robot_id_,errmm__);
        log(robot_id_, errmm__);
        raise_application_error (-20012, errmm__, TRUE);
      end loop;
    end if;
  end if;


  insert into command_inner (command_type_id, rp_id,
         cell_src_sname, cell_src_id, track_src_id, npp_src,
         cell_dest_sname, cell_dest_id, track_dest_id, npp_dest,
         track_npp_begin,
         state, command_rp_id, robot_id, command_to_run, direction, container_id, check_point)
  values (cmd_inner_type_,rob_rec__.repository_part_id,
          cell_src_sname_, ci_rec__.cell_src_id, ci_rec__.track_src_id, ci_rec__.npp_src,
          cell_dest_sname_, ci_rec__.cell_dest_id, ci_rec__.track_dest_id, ci_rec__.npp_dest,
          rob_rec__.current_track_npp,
          1, crp_id_, robot_id_, cmd_text_, dir_, container_id_, check_point_)
  returning id into ciid__;
  update robot set command_inner_assigned_id=ciid__ where id=robot_id_;
  log(robot_id_,'Успешно назначили cmd_inner id='||ciid__);
end;

-- снимает назначенную команду с робота, если еще процесс не пошел
procedure Cmd_RP_Cancel(robot_id_ number) is
  err__ varchar2(4000);
  cnt__ number;
begin
  Log(robot_id_,'');
  Log(robot_id_,'****************************************************');
  Log(robot_id_,'Пришел запрос на отмену command_rp с робота');
  for rr in (select * from robot
             where id=robot_id_ and nvl(command_rp_id,0)>0
                   and nvl(command_inner_id,0)=0
                   and nvl(command_inner_assigned_id,0)=0) loop
    select count(*) into cnt__ from command_inner where command_rp_id=rr.command_rp_id;
    if cnt__=0 then
      Log(robot_id_,'  вроде можно отменить, отменяем');
      update command_rp
      set robot_id=null, direction_1=null, direction_2=null
      where id=rr.command_rp_id;
      update robot set command_rp_id=0 where id=robot_id_;
      for cii in (select * from command_inner where robot_id=robot_id_ and state=3 and command_type_id=32) loop
        Log(robot_id_,'  была команда InitY с ID='||cii.id||', удаляем');
        delete from command_inner where id=cii.id;
      end loop;
      commit;

      return;
    else
      err__:='  ERROR - Нет возможности отменить назначенную command_rp с робота - есть CI';
      Log(robot_id_,err__);
      raise_application_error (-20003, err__);
    end if;
  end loop;
  err__:='  ERROR - Нет возможности отменить назначенную command_rp с робота';
  Log(robot_id_,err__);
  raise_application_error (-20003, err__);
end;


-- получить текст команды робота по ID робота
function Get_Cmd_Inner_Txt(rid_ number) return varchar2 is
begin
  for rr in (select /*+RULE*/ ci.command_to_run
             from robot r, command_inner ci
             where r.id=rid_ and nvl(r.command_inner_id,0)=ci.id) loop
    return rr.command_to_run;
  end loop;
  return '';
end;

-- получить тип команды робота по ID робота
function Get_Cmd_Inner_Type(rid_ number) return number is
begin
  for rr in (select /*+RULE*/ ci.command_type_id
             from robot r, command_inner ci
             where r.id=rid_ and nvl(r.command_inner_id,0)=ci.id) loop
    return rr.command_type_id;
  end loop;
  return -1;
end;


-- получить имя ячейки-источника для команды перемещения контейнера по ID робота
function Get_Cmd_Cell_Src(rid_ number) return varchar2 is
begin
  for rr in (select /*+RULE*/ crp.cell_src_sname
             from robot r, command_rp crp
             where r.id=rid_ and nvl(r.command_rp_id,0)=crp.id) loop
    return rr.cell_src_sname;
  end loop;
  return '';
end;

-- получить имя ячейки назначения для команды перемещения контейнера по ID робота
function Get_Cmd_Cell_Dest(rid_ number) return varchar2 is
begin
  for rr in (select /*+RULE*/  crp.cell_dest_sname
             from robot r, command_rp crp
             where r.id=rid_ and nvl(r.command_rp_id,0)=crp.id) loop
    return rr.cell_dest_sname;
  end loop;
  return '';
end;

-- получить ШК контейнера команды перемещения контейнера по ID робота
function Get_Cmd_Container(rid_ number) return varchar2 is
begin
  for rr in (select /*+RULE*/ cnt.barcode
             from robot r, command_rp crp, container cnt
             where r.id=rid_ and nvl(r.command_rp_id,0)=crp.id and crp.container_id=cnt.id) loop
    return rr.barcode;
  end loop;
  return '';
end;

-- получить направление команды перемещения контейнера по ID робота (доп. параметр - часть команды)
function Get_Cmd_Dir(rid_ number, nnm_ number default 1) return number is
begin
  for rr in (select /*+RULE*/ crp.direction_1, crp.direction_2
             from robot r, command_rp crp
             where r.id=rid_ and nvl(r.command_rp_id,0)=crp.id) loop
    if nnm_=1 then
      return rr.direction_1;
    else
      return rr.direction_2;
    end if;
  end loop;
  return null;
end;

-- назначает команду на SQL сервере на робота с оптимизатора Sarmat
procedure Set_CmdRP(crp_ID_ number, Robot_ID_ number, Dir1_ number, Dir2_ number, Calc_Cost_ number, Pri_Inner_ number) is
  errm__ varchar2(4000);
  cnt__ number;
begin
  Log(robot_id_,'Пришло назначение команды '||crp_ID_||' на робота '||Robot_id_||' Dir1='||dir1_||' Dir2='||dir2_||' calc_cost='||calc_cost_||' Pri_Inner_='||Pri_Inner_);
  select count(*) into cnt__ from command_rp where id=crp_ID_;
  if cnt__=0 then -- уже удалили команду, отбой
       errm__:='ERROR - ошибка назначения команды - command_rp с id='||crp_ID_||' уже удалена!';
       Log(robot_id_,errm__);
       raise_application_error (-20003, errm__, TRUE);
  end if;
  select count(*) into cnt__ from robot
    where id=Robot_ID_ and not (nvl(command_rp_id,0) in (0, crp_ID_));
  if cnt__>0 then -- уже есть какая-то назначенная команда, отбой
       errm__:='ERROR - ошибка назначения команды - на робота уже есть команда command_rp';
       Log(robot_id_,errm__);
       raise_application_error (-20003, errm__, TRUE);
  else
    begin
      update robot set command_rp_id=crp_ID_ where id=Robot_ID_;
      update command_rp
      set
        robot_id=robot_id_,
        direction_1=dir1_,
        direction_2=dir2_,
        calc_cost=Calc_Cost_,
        substate=1,
        date_time_begin=sysdate,
        Priority_Inner=Pri_Inner_
      where id=crp_id_;
      commit;
      Log(robot_id_,'  команда успешно назначилась');
    exception when others then
       errm__:='ERROR - ошибка назначения команды '||SQLERRM;
       Log(robot_id_,errm__);
       raise_application_error (-20003, errm__, TRUE);
    end;
  end if;
end;

-- робот готов для команд перемещения контейнера?
function Is_Robot_Ready_For_Cmd(rid_ number, not_connected_is_ready_ boolean default false) return number is
  ncir number;
begin
  ncir:=0;
  if not_connected_is_ready_ then
    ncir:=1;
  end if;
  for rr in (select * from robot
             where id=rid_
               and ((state=0) or (ncir=1 and state in (0,8)))
               and is_present=1
               and nvl(command_rp_id,0)=0
               and nvl(command_inner_assigned_id,0)=0
               and nvl(command_inner_id,0)=0
               and nvl(wait_for_problem_resolve,0)=0) loop
    return 1;
  end loop;
  return 0;
end;

-- робот готов для подкоманд перемещения контейнера (load/unload)?
function Is_Robot_Ready_For_Cmd_Inner(rid_ number) return number is
begin
  for rr in (select * from robot
             where id=rid_
               and state=0
               and is_present=1
               and nvl(command_inner_assigned_id,0)=0
               and nvl(command_inner_id,0)=0
               and nvl(wait_for_problem_resolve,0)=0) loop
    return 1;
  end loop;
  return 0;
end;

-- получить сколько времени в секундах уже работает команда работа (но не более 6 минут)
function Get_Cmd_Inner_Time_Work(cid_ number) return number is
  delta__ number;
  max_d__ number;
begin
  max_d__:=1/(24*10);
  for ci__ in (select * from command_inner where id=cid_) loop
     delta__:=sysdate-nvl(ci__.date_time_begin, ci__.date_time_create);
     if delta__>=max_d__ then
       return round(max_d__*24*60*60);
     else
       return round(delta__*24*60*60);
     end if;
  end loop;
  return -1;
end;

-- получить дату-время начала команды робота по ID
function get_cmd_inner_dtb(cid_ number) return date is
begin
  for ci__ in (select * from command_inner where id=cid_) loop
    return ci__.date_time_begin;
  end loop;
  return null;
end;

-- получить тип команда для имитационного моделирования (с учетом перемещений попромежуточным точкам)
function Get_Cmd_Inner_Imi_Type(cid_ number) return number is
  cp_npp_ number;
  dest_ number;
begin
  for ci in (select * from command_inner where id=cid_) loop
    if ci.command_type_id=CMD_MOVE_TYPE_ID then
      return ci.command_type_id;
    elsif ci.check_point is null then
      return ci.command_type_id;
    else
      cp_npp_:=Get_Cmd_Inner_Last_Checkpoint(cid_);
      dest_:=Get_Cmd_Inner_Npp_Dest(cid_);
      if cp_npp_=dest_ then
        return ci.command_type_id;
      else
        return CMD_MOVE_TYPE_ID;
      end if;
    end if;
  end loop;
end;


-- получить № целевого трека команды робота
function Get_Cmd_Inner_Npp_Dest(cid_ number, is_use_cp_ number default 0) return number is
  res_ number;
begin
  for ci__ in (select * from command_inner where id=cid_) loop
     if is_use_cp_=1 and ci__.check_point is not null then -- есть промежуточные точки
       res_:=ci__.check_point;
       for chp in (select * from command_inner_checkpoint where command_inner_id=cid_ order by id desc) loop
         res_:=chp.npp;
         exit;
       end loop;
       return res_;
     else
       if ci__.command_type_id =CMD_LOAD_TYPE_ID then
         return ci__.npp_src;
       else
         return ci__.npp_dest;
       end if;
     end if;
  end loop;
  return -1;
end;

-- сменить у робота режим "Only Move"
procedure change_only_move_status(rid_ number) is
  cnt number;
  nor number;
  iw number;
  errm__ varchar2 (1000);
begin
  for rr in (select * from robot where id=rid_) loop
    select num_of_robots into nor from repository_part where id=rr.repository_part_id;
    select is_work into iw from repository;
    if rr.forbid_load_unload=0 then -- проверить бы надо, не все ли роботы склада сейчас станут MoveOnly
      select count(*) into cnt from robot where repository_part_id=rr.repository_part_id and forbid_load_unload=1;
      if cnt=nor-1 then
        errm__:='ERROR - нельзя делать MoveOnly все роботы подсклада!';
        Log(rid_,errm__);
        raise_application_error (-20003, errm__, TRUE);
      end if;
    end if;
    if iw=1 and rr.forbid_load_unload=0 then
        errm__:='ERROR - нельзя делать робота MoveOnly в работающем АСК! Поставьте АСК на паузу вначале!';
        Log(rid_,errm__);
        raise_application_error (-20003, errm__, TRUE);
    end if;
    update robot
    set forbid_load_unload=decode(forbid_load_unload,0,1,0)
    where id=rid_;
    commit;
  end loop;
end;

-- получение информации о дополнительных параметрах для перевода робота в режим почники по ID робота
function get_repair_stop_param(rid_ number) return number is
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

-- выйти из режима починки робота в нормальный рабочий режим
function set_repair_done(rid_ number) return varchar2 is
begin
  update robot set state=0 where id=rid_;
  commit;
  return '';
end;


-- взять ШК контейнера команды перемещения контейнера по id роботу
function get_ci_cnt_bc(rid_ number) return varchar2 is
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

-- возвращает последнюю команду _inner от компьютера оператора
function get_last_comp_ci(comp_name_ varchar2) return number is
begin
  for cg in (select * from command_gas where comp_name=comp_name_ and state not in (2,5) order by id desc) loop
    for cc in (select ci.*
               from command cmd, command_rp crp, command_inner ci
               where cmd.command_gas_id=cg.id and crp.command_id=cmd.id and crp.id=ci.command_rp_id
                     and ci.state not in (2,5)
               order by ci.id desc) loop

      return cc.id;
    end loop;
    exit;
  end loop;
  return 0;
end;

-- берем простой вариант запроса для решения проблемы (Да/нет), чтобы потом задать его оператору
function get_problem_resolve_text(comp_name_ varchar2) return varchar2 is
  ci_id_ number;
begin
  ci_id_:=get_last_comp_ci(comp_name_);
  if ci_id_>0 then
    for cc in (select ci.*, r.platform_busy
               from command_inner ci, robot r
               where ci.id=ci_id_ and ci.state not in (2,5) and r.id=ci.robot_id
               order by ci.id desc) loop
      for pr in (select * from problem_resolving where command_type_id=cc.command_type_id
                       and (platform_busy is null or nvl(platform_busy,-1)=cc.platform_busy)) loop
         return pr.text;
      end loop;
      exit;
    end loop;
  end if;
  return '';
end;


-- взять имя ячейки источника команды робота по id роботу
function get_ci_cell_src(rid_ number) return varchar2 is
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

-- взять имя ячейки назначения команды робота по id роботу
function get_ci_cell_dst(rid_ number) return varchar2 is
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


-- перевести робота в режим починки
function set_mode_to_repair(rid_ number, npp_rep number, param number) return varchar2 is
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
    set robot_id=null, state=1, direction_1=null, direction_2=null, substate=null, calc_cost=null, date_time_begin=null
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
  log(rid_,'set_mode_to_repair - начало');

  for rob in (select * from robot where id=rid_) loop

    for rp in (select id, spacing_of_robots sorb, max_npp from repository_part where id=rob.repository_part_id) loop


      if rob.state=6 then
        return 'Robot is already in repair mode!';
      end if;
      for tr in (select * from track where repository_part_id=rob.repository_part_id and npp=npp_rep) loop
        tid_rep:=obj_rpart.get_track_id_by_robot_and_npp(rid_, npp_rep);

        npp1:=obj_rpart.inc_spacing_of_robots(npp_rep, 1, rp.sorb, rp.id);
        npp2:=obj_rpart.inc_spacing_of_robots(npp_rep, obj_rpart.get_another_direction(1), rp.sorb, rp.id);
        if service.is_way_free_for_robot(rid_, npp2, npp1)<>1 then
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

        -- были ли команда назначена , но не выдана?
        if nvl(rob.command_inner_id,0)=0 and nvl(rob.command_inner_assigned_id,0)<>0 then
          for ci in (select * from command_inner where id=nvl(rob.command_inner_assigned_id,0)) loop
             cancel_command(ci.id, ci.command_rp_id);
          end loop;
        end if;

        -- были ли команды назначенные имит.моделированием, но не дошедшие до робота
        update command_rp crps
        set date_time_begin=null, robot_id=null, direction_1=null, direction_2=null, substate=null, calc_cost=null
        where nvl(robot_id,0)=rid_ and state=1 and not exists (select * from command_inner where command_rp_id=crps.id);

        -- универсальные действия независимо от
        update track set locked_by_robot_id=0 where locked_by_robot_id=rid_;
        insert into robot_trigger_ignore(robot_id) values(rid_);
        --ie_tools.disable_table_trigger('ROBOT');
        begin
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
        exception when others then
          delete from robot_trigger_ignore where robot_id=rid_;
          raise_application_error (-20003, SQLERRM);

        end;
        delete from robot_trigger_ignore where robot_id=rid_;
        --ie_tools.enable_table_trigger('ROBOT');
        --tl1:=manager.try_to_lock(rid_, npp_rep,1,-1 );

        tl1:=obj_rpart.Try_Track_Lock_Robot_Around(rid_ , npp_rep);

        if tl1<>1 then
          rollback;
          return 'Attempt to lock new track area was failed!';
        end if;
        commit;
        delete from track_order where robot_id=rid_;
        commit;

        return '';
      end loop;
      return 'Track '||npp_rep||' is not in repository '||rob.repository_part_id||'!';

    end loop;
    return 'Repository part is not found for robot!';
  end loop;
  return 'Robot ID='||rid_||' is not found!';

end;

-- изменить целевую ячейку команды для робота (Unload)
procedure change_cmd_unload_goal(cmd_inner_id_ number, new_cell_goal_id_ number) is
  old_rp command_rp%rowtype;
begin
  for ci in (select ci.*, cn.type cnt_type from command_inner ci, container cn
             where ci.id=cmd_inner_id_ and command_type_id=CMD_UNLOAD_TYPE_ID and ci.state in (0,1,3)
                   and container_id=cn.id
            ) loop
    for cl in (select * from cell where id=new_cell_goal_id_ and is_full=0 and cell_size<=ci.cnt_type
                and not exists (select * from command_rp where cell_dest_id=cell.id and state in (0,1,3))) loop

       select * into old_rp from command_rp where id=ci.command_rp_id;
       for cc in (select c.sname, s.track_id , t.npp, hi_level_type
                  from cell c, shelving s, track t
                  where c.id=new_cell_goal_id_ and c.shelving_id=s.id and s.track_id=t.id) loop
           update cell_cmd_lock
           set cell_id = new_cell_goal_id_, sname=cc.sname
           where cell_id=ci.cell_dest_id and cmd_id=old_rp.command_id;
         update command_rp
         set
           cell_dest_id=new_cell_goal_id_,
           cell_dest_sname =cc.sname,
           track_dest_id = cc.track_id,
           npp_dest = cc.npp
         where id=ci.command_rp_id;
         if cc.hi_level_type=1 then -- выгружаем на хранение
           for crp in (select * from command_rp where id=ci.command_rp_id) loop
             update command
             set
               cell_dest_sname=cc.sname,
               cell_dest_id=new_cell_goal_id_,
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
         end if;
       end loop;
       -- если ошибка выгрузки в занятую ячейку, то разруливаем
       for ci in (select ci.* from command_inner ci, robot r
                  where ci.id=cmd_inner_id_ and ci.state=3 and robot_id=r.id and wait_for_problem_resolve=1) loop
         update command_inner set state=2 where id=ci.id;
         update robot
         set
           wait_for_problem_resolve=0,
           command_inner_id =null,
           command_inner_assigned_id =0
         where id=ci.robot_id;
       end loop;
       commit;
       return;
    end loop;
    raise_application_error (-20003, 'неверная новая целевая ячейка '||cmd_inner_id_, TRUE);
  end loop;
  raise_application_error (-20003, 'неверная команда '||cmd_inner_id_, TRUE);
end;

-- перенаправить робота в новую целевую ячейку (Unload)
procedure Redirect_Robot_To_New_Cell(robot_id_ number, cmd_rp_id_ number, container_id_ number, ci_npp_dest_ number, ci_cell_dest_id_ number) is
  cellrec cell%rowtype;
  direction_ number;
begin
  for rr in (select * from robot where id=robot_id_ and PLATFORM_BUSY=1) loop
    if obj_rpart.has_free_cell_by_cnt(container_id_, rr.repository_part_id)>0 -- есть еще место на складе
        and ci_npp_dest_=rr.current_track_npp  -- чтоб точно быть уверенным, что дело именно в этом
        and obj_rpart.is_poss_ass_new_unload_cell(ci_cell_dest_id_, robot_id_ )=1 -- а можно ли выгрузить в какую-нить другую ячейку  принципе?
    then
       obj_rpart.try_assign_new_unload_cell(ci_cell_dest_id_, robot_id_, cellrec, direction_);
       if cellrec.track_npp is not null then
         update robot set state=0, command_inner_id=Null, cmd_error_descr=Null
         where id=robot_id_;
         --update command_inner set state=2, error_code_id=error_code  where id=cirec.id;
         --update cell set is_error=1 where id=cirec.cell_dest_id;
         obj_rpart.change_cmd_rp_goal(cmd_rp_id_,cellrec.id);
         update command_rp set substate=3, direction_2=direction_ where id=cmd_rp_id_;
         return;
       end if;
    end if;
  end loop;
  raise_application_error (-20003, 'Невозможно перенаправить робота в другую ячейку!', TRUE);

end;

-- возвращает в XML варианты решения проблемы
function get_robot_problem_resolve_cs(rid_ number) return varchar2 is
  doc xmldom.DOMDocument;
  root_node xmldom.DOMNode;
  main_node xmldom.DOMNode;
  root_elmt xmldom.DOMElement;
  user_node xmldom.DOMNode;
  item_elmt xmldom.DOMElement;
  res varchar2(4000);

begin
  for rr in (select * from robot where id=rid_ and nvl(wait_for_problem_resolve,0)=1) loop
    doc := xmldom.newDOMDocument;
    main_node := xmldom.makeNode(doc);
    root_elmt := xmldom.createElement(doc, 'RPRW');
    root_node := xmldom.appendChild(main_node, xmldom.makeNode(root_elmt));
    for ci in (select * from command_inner where id=nvl(rr.command_inner_id,0)) loop
      for pr in (select * from problem_resolving pr where command_type_id=ci.command_type_id and rr.platform_busy=nvl(pr.platform_busy,rr.platform_busy) order by order_) loop
         item_elmt := xmldom.createElement(doc, 'Case'    );
         xmldom.setAttribute(item_elmt, 'id', pr.id);
         xmldom.setAttribute(item_elmt, 'name', pr.text);
         if pr.question is not null then
           xmldom.setAttribute(item_elmt, 'question', pr.question);
         end if;
         user_node := xmldom.appendChild(root_node , xmldom.makeNode(item_elmt));
      end loop;
    end loop;
    xmldom.writetobuffer(doc, res);
    xmldom.freeDocument(doc);
    return res;
  end loop;
  return '';
end;

-- изменить направление команды робота на противоположное
procedure change_wpr_dir(ci_id_ number, new_dir_ number) is
begin
  for ci in (select * from command_inner where id=ci_id_) loop
    update command_inner
    set direction=new_dir_,
        command_to_run=get_cmd_text_another_dir(command_to_run)
    where id=ci.id;
    obj_rpart.Robot_Cmd_RP_Change_Dir(ci.robot_id);
  end loop;
end;

-- возвращает текст команды робота с иным направлением движения по/против часовой стрелке
function get_cmd_text_another_dir(ct varchar2) return varchar2 is
  res varchar2(250);
begin
  if instr(ct,'CCW')>0 then
    res:=replace(ct, 'CCW', '');
  else
    res:=replace(ct, ';;', ';CCW;');
  end if;
  return res;
end;

-- возвращает робота, который делал команду перемещения контейнеров
function get_cmd_robot_name(cmd_id_ number) return varchar2 is
begin
  for rr in (select r.name from command_rp crp, robot r
             where command_id=cmd_id_ and crp.robot_id=r.id Order by crp.id desc) loop
    return rr.name;
  end loop;
  return '';
end;

-- возвращает ID и NPP промежуточной точки команды, или -1 если нет такой - для сервера штабелров для команды checkpoint
function Get_Cmd_Inner_Checkpoint(cmd_inner_id_ number) return varchar2 is
  new_id_ number;
  last_sended_ date;
begin
  for ci in (select * from command_inner where id=cmd_inner_id_ and (sysdate-nvl(date_time_begin,sysdate))>1/(24*60*(60/5)) ) loop -- чтоб после начала слало только
    last_sended_:=sysdate-1;
    for ls_ in (select DATE_TIME_SENDED 
                from command_inner_checkpoint 
                where cmd_inner_id_=command_inner_id and DATE_TIME_SENDED is not null order by DATE_TIME_SENDED desc) loop
      last_sended_:=ls_.DATE_TIME_SENDED;
      exit;
    end loop;
    if sysdate-last_sended_<=1/(24*60*(60/3)) then -- еще слишком мало прошло времени с последней подачи команды промежуточной
      dbms_output.put_line('Слишком рано '||to_char(last_sended_,'dd.mm.yy hh24:mi:ss'));
      return '-1';
    end if;
    for rr in (select * from robot where id=ci.robot_id and nvl(wait_for_problem_resolve,0)=0 and state=1) loop -- только для работающего робота не в состоянии ошибки
      for chp in (select * from command_inner_checkpoint where cmd_inner_id_=command_inner_id and status<3 order by id desc) loop
        if chp.npp=Get_Cmd_Inner_Npp_Dest(cmd_inner_id_) then
            if nvl(chp.gv_ci_id,0)>0 then
              new_id_:=chp.gv_ci_id;
              --update command_inner_checkpoint set DATE_TIME_SENDED=sysdate where id=chp.id;
            else
              new_id_:=SEQ_command_inner.nextval;
              update command_inner_checkpoint set gv_ci_id =new_id_ /*, DATE_TIME_SENDED=sysdate */ where id=chp.id;
            end if;
            commit;
            return new_id_||';-1'; -- уже достигли конечной точки, передает необходимость delete checkpoint
        else
          if nvl(chp.gv_ci_id,0)>0 then
            new_id_:=chp.gv_ci_id;
            --update command_inner_checkpoint set DATE_TIME_SENDED=sysdate where id=chp.id;
          else
            new_id_:=SEQ_command_inner.nextval;
            update command_inner_checkpoint set gv_ci_id =new_id_/*, DATE_TIME_SENDED=sysdate */where id=chp.id;
          end if;
          commit;
          return new_id_||';'||chp.npp;
        end if;
      end loop;
    end loop;
  end loop;
  return '-1';
end;

-- возвращает NPP последней промежуточной точки команды, или -1 если нет такой
function Get_Cmd_Inner_Last_Checkpoint(cmd_inner_id_ number, in_status_ number default null) return number is
begin
  for ci in (select * from command_inner where id=cmd_inner_id_ and check_point is not null) loop
    for chp in (select * from command_inner_checkpoint where cmd_inner_id_=command_inner_id and status=nvl(in_status_,status) order by id desc) loop
      return chp.npp;
    end loop;
    return ci.check_point;
  end loop;
  return -1;
end;


-- пометить промежуточные точки как посланные роботу
procedure Mark_CI_CP_Send_To_Robot(cpcg_id_ number, new_status_ number default 1) is
begin
  for cpf in (select * from command_inner_checkpoint  where gv_ci_id=cpcg_id_) loop
    update command_inner_checkpoint
    set status=new_status_
    where command_inner_id=cpf.command_inner_id and id<=cpf.id and status<>new_status_;
    if new_status_=1 then
      update command_inner_checkpoint set DATE_TIME_SENDED=sysdate where id=cpf.id ;
    else
      update command_inner_checkpoint set DATE_TIME_ACC_ROBOT=sysdate where id=cpf.id and DATE_TIME_ACC_ROBOT is null;
    end if;
    commit;
  end loop;
end;

-- исключает 'cp=NNN' из текста команды
function Get_Cmd_Text_WO_cp(ct_ varchar2) return varchar2 is
  lp_ number;
  sc_ number;
  ncitext varchar2(300);
begin
  ncitext:=ct_;
  lp_:=instr(ncitext,'cp');
  if lp_>0 then
    sc_:=instr(ncitext,';');
    if sc_<=0 then
      return(trim(substr(ncitext,1,lp_-1)));
    else
      return(trim(substr(ncitext,1,lp_-1))||substr(ncitext,sc_));
    end if;
  else -- и так нет
    return ncitext;
  end if;
end;

-- заменяет 'cp=NNN' в тексте команды на другую секцию
function Get_Cmd_Text_New_cp(ct_ varchar2, new_cp_ number) return varchar2 is
  lp_ number;
  sc_ number;
  ncitext varchar2(300);
begin
  ncitext:=Get_Cmd_Text_WO_cp(ct_); -- убрали, если было
  lp_:=instr(ncitext,';');
  if new_cp_ is null then
    raise_application_error (-20003, 'Нельзя менять промежуточную секцию на пустоту!', TRUE);
  end if;
  if lp_>0  then -- есть ;
    return trim(substr(ncitext,1,lp_-1))||' cp='||new_cp_||substr(ncitext,lp_);
  else -- нет ';', просто лупим в конец
    return ncitext||' cp='||new_cp_;
  end if;

end;

-- возвращает строку лога работы с промежуточными точками по команде
function Get_Cmd_Inner_CP_Process(cmd_inner_id_ number) return varchar2 is
  res_ varchar2(100);
  tmp_ number;
begin
  res_:='';
  for cc in (select * from command_inner where id=cmd_inner_id_) loop
    for rr in (select * from robot where id=cc.robot_id and is_use_checkpoint=1)  loop
      tmp_:=null;
      for chp in (select * from command_inner_checkpoint where cmd_inner_id_=command_inner_id order by id desc) loop
        tmp_:=chp.npp;
        exit;
      end loop;
      if tmp_ is null then
        return '-';
      else
        res_:=tmp_||'/';
        tmp_:=null;
        for chp in (select * from command_inner_checkpoint where cmd_inner_id_=command_inner_id and status=3 order by id desc) loop
          tmp_:=chp.npp;
          exit;
        end loop;
        if tmp_ is null then
          return res_||'-';
        else
          return res_||tmp_;
        end if;
      end if;
    end loop;
  end loop;
  return res_;
end;



end obj_robot;
/
