create or replace trigger command_inner_au_state
after update of state, problem_resolving_id
ON command_inner
declare
 cirec command_inner%rowtype;
 rr robot%rowtype;
 cnid number;
 cnt number;
 ncitext varchar2(250);
 newcmddir number;
 lp_ number;
 cmd_dest_ number;
BEGIN
 for tcii in (select * from tmp_cmd_inner  where action is null order by ci_id) loop
     select * into cirec from command_inner where id=tcii.ci_id;

     -- смотрим, а не надо ли разблокировать зря заблокированное при отмене  юстировки
     if cirec.command_type_id=6
       and nvl(cirec.command_rp_id,0)<>0
       and nvl(cirec.command_rp_id,0)<>-1
       then -- было MOVE и было по команде
       for rbl in (select * from command
                   where id=(select command_id from command_rp where id=cirec.command_rp_id)
                         and state=2
                         and command_type_id=19) loop
         service.unlock_all_not_ness(cirec.robot_id);
       end loop;
     end if;

     update command_rp
     set
       command_inner_last_robot_id=cirec.robot_id,
       command_inner_executed=cirec.id,
       error_code_id=cirec.error_code_id
     where id=cirec.command_rp_id;
     delete from tmp_cmd_inner where ci_id=tcii.ci_id and action is null;
 end loop;

 -- пометить все исходные команды как плохие
 for tcii in (select * from tmp_cmd_inner  where nvl(action,'-') ='B' order by ci_id) loop
     select * into cirec from command_inner where id=tcii.ci_id;
     delete from tmp_cmd_inner where ci_id=tcii.ci_id and nvl(action,'-') ='B';

     for crp in (select * from command_rp where id=cirec.command_rp_id) loop
       update command_rp set state=2 where id=crp.id;
       for cmd in (select * from command where id=crp.command_id) loop
         update command set state=2 where id=cmd.id;
         for cg in (select * from command_gas where id=cmd.command_gas_id) loop
           update command_gas set state=2 where id=cg.id;
         end loop;
       end loop;
     end loop;
 end loop;


 -- повторить команду
 for tcii in (select * from tmp_cmd_inner  where nvl(action,'-')='R' order by ci_id) loop
     select * into cirec from command_inner where id=tcii.ci_id;
     select * into rr from robot where id=cirec.robot_id;
     cnt:=instr(cirec.command_to_run,';',-1);
     ncitext:=substr(cirec.command_to_run,0,cnt-1);

     newcmddir:=cirec.direction;
     if cirec.command_type_id  in (6,5) then -- move/unload
       if obj_rpart.is_way_free(rr.id,obj_robot.Get_Cmd_Inner_Npp_Dest(cirec.id,1),cirec.direction)<>1 then
         newcmddir:=obj_rpart.get_another_direction(newcmddir);
         if obj_rpart.is_way_free(rr.id,cirec.npp_dest,newcmddir)<>1 then
           raise_application_error (-20012, 'Crash alarm! The way is busy for robot '||rr.id||' to track '||cirec.npp_dest||' on all directions!');
         else
           ncitext:=obj_robot.get_cmd_text_another_dir(ncitext);
         end if;
       end if;
     elsif cirec.command_type_id in (4) then -- load
       if obj_rpart.is_way_free(rr.id,obj_robot.Get_Cmd_Inner_Npp_Dest(cirec.id,1),cirec.direction)<>1 then
         newcmddir:=obj_rpart.get_another_direction(newcmddir);
         if obj_rpart.is_way_free(rr.id,cirec.npp_dest,newcmddir)<>1 then
           raise_application_error (-20012, 'Crash alarm! The way is busy for robot '||rr.id||' to track '||cirec.npp_src||' on all directions!');
         else
           ncitext:=obj_robot.get_cmd_text_another_dir(ncitext);
         end if;
       end if;
     end if;

     if cirec.check_point is null then -- нет промежуточных точек
       insert into command_inner (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
         state, command_rp_id, robot_id, command_to_run, track_src_id,
         track_dest_id, direction, cell_src_id, cell_dest_id,
         npp_src, npp_dest,
         track_id_begin, track_npp_begin,
         cell_sname_begin, container_id)
       values (cirec.command_type_id, cirec.rp_id, cirec.cell_src_sname, cirec.cell_dest_sname,
         1, cirec.command_rp_id, cirec.robot_id, ncitext, cirec.track_src_id,
         cirec.track_dest_id, newcmddir, cirec.cell_src_id, cirec.cell_dest_id,
         cirec.npp_src, cirec.npp_dest,
         rr.current_track_id , rr.current_track_npp ,
         obj_rpart.Get_Cell_Name_By_Track_ID(rr.current_track_id), cirec.container_id)
       returning id into cnid;
     else -- есть промежуточные точки
       lp_:=obj_robot.Get_Cmd_Inner_Last_Checkpoint(cirec.id);
       cmd_dest_:=obj_robot.Get_Cmd_Inner_Npp_Dest(cirec.id);
       if lp_=cmd_dest_ or rr.current_track_npp=cmd_dest_  then -- уже открыт проход куда надо или находимся там где надо
         ncitext:=obj_robot.Get_Cmd_Text_WO_cp(ncitext);
         insert into command_inner (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
           state, command_rp_id, robot_id, command_to_run, track_src_id,
           track_dest_id, direction, cell_src_id, cell_dest_id,
           npp_src, npp_dest,
           track_id_begin, track_npp_begin, cell_sname_begin, container_id)
         values (cirec.command_type_id, cirec.rp_id, cirec.cell_src_sname, cirec.cell_dest_sname,
           1, cirec.command_rp_id, cirec.robot_id, ncitext, cirec.track_src_id,
           cirec.track_dest_id, newcmddir, cirec.cell_src_id, cirec.cell_dest_id,
           cirec.npp_src, cirec.npp_dest,
           rr.current_track_id , rr.current_track_npp ,
           obj_rpart.Get_Cell_Name_By_Track_ID(rr.current_track_id), cirec.container_id)
           returning id into cnid;
       else
         ncitext:=obj_robot.Get_Cmd_Text_New_cp(ncitext,lp_);
         insert into command_inner (command_type_id, rp_id, cell_src_sname, cell_dest_sname,
           state, command_rp_id, robot_id, command_to_run, track_src_id,
           track_dest_id, direction, cell_src_id, cell_dest_id,
           npp_src, npp_dest,
           track_id_begin, track_npp_begin, cell_sname_begin, container_id, check_point)
         values (cirec.command_type_id, cirec.rp_id, cirec.cell_src_sname, cirec.cell_dest_sname,
           1, cirec.command_rp_id, cirec.robot_id, ncitext, cirec.track_src_id,
           cirec.track_dest_id, newcmddir, cirec.cell_src_id, cirec.cell_dest_id,
           cirec.npp_src, cirec.npp_dest,
           rr.current_track_id , rr.current_track_npp ,
           obj_rpart.Get_Cell_Name_By_Track_ID(rr.current_track_id), cirec.container_id, lp_)
           returning id into cnid;
       end if;
     end if;
     update robot set command_inner_assigned_id=cnid where id=rr.id;
     delete from tmp_cmd_inner where ci_id=tcii.ci_id and nvl(action,'-')='R';
 end loop;

 -- обновляем текущее нахождение контейнера для приема товара command_gas
 for tcii in (select * from tmp_cmd_inner  where nvl(action,'-')='G' order by ci_id) loop
   select * into cirec from command_inner where id=tcii.ci_id;
   for cg in (select cg.id from command_rp crp, command c, command_gas cg
              where crp.id=cirec.command_rp_id and crp.command_id=c.id and
                    c.command_gas_id=cg.id and cg.command_type_id=11) loop
     update command_gas
     set
       container_cell_name=cirec.cell_dest_sname ,
       container_rp_id=cirec.rp_id
     where id=cg.id;
   end loop;
   delete from tmp_cmd_inner where ci_id=tcii.ci_id and nvl(action,'-')='G';
 end loop;

 -- помечаем что контейнер на платформе
 for tcii in (select * from tmp_cmd_inner  where nvl(action,'-')='L' order by ci_id) loop
   select * into cirec from command_inner where id=tcii.ci_id;
   for cg in (select cg.id from command_rp crp, command c, command_gas cg
              where crp.id=cirec.command_rp_id and crp.command_id=c.id and
                    c.command_gas_id=cg.id and cg.command_type_id=11) loop
     update command_gas
     set
       container_cell_name='' ,
       container_rp_id=cirec.rp_id
     where id=cg.id;
   end loop;
   delete from tmp_cmd_inner where ci_id=tcii.ci_id and nvl(action,'-')='L';
 end loop;


 -- помечаем что команда command назначена уже
 for tcii in (select * from tmp_cmd_inner  where nvl(action,'-')='N' order by ci_id) loop
   select * into cirec from command_inner where id=tcii.ci_id;
   update command set state=3
   where
     id =(select command_id from command_rp where id=cirec.command_rp_id)
     and state<3 and state<>2;
   delete from tmp_cmd_inner where ci_id=tcii.ci_id and nvl(action,'-')='N';
 end loop;



END;
/
