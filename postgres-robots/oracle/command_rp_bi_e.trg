CREATE OR REPLACE TRIGGER command_rp_bi_e
BEFORE INSERT
ON command_rp
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 error_name varchar2(250);
 rbr number;
BEGIN
 :new.user_name:=user;

 if :new.ID is null then
   SELECT SEQ_command_rp.nextval INTO :new.ID FROM dual;
   :new.date_time_create:=sysdate;
   :new.time_create:=systimestamp;
 end if;

 -- для простого перемещения считаем идеальную цену
 if :new.command_type_id=3 then
   :new.ideal_cost:=service.calc_ideal_crp_cost(:new.rp_id , :new.cell_src_id , :new.cell_dest_id );
   -- проверяем, свободна ли ячейка-приемник, и есть ли что в ячейке-источнике
   if service.is_cell_full_check=1 then
     for cs in (select * from cell where id=:new.cell_src_id) loop
       if cs.is_full<1 then
         raise_application_error (-20000-6, 'ERROR: cell-source '||:new.cell_src_sname||' is empty', TRUE);
       end if;
     end loop;
     for cd in (select * from cell where id=:new.cell_dest_id) loop
       if cd.is_full>=cd.max_full_size  then
         raise_application_error (-20000-6, 'ERROR: cell-destination '||:new.cell_dest_sname||' is overfull', TRUE);
       end if;
     end loop;
   end if;


 -- **************************************
 -- для перемещения робота проверки
 elsif  :new.command_type_id=30 then
   if nvl(:new.robot_id,0)=0 then
     raise_application_error(-20070,'Empty robot_id!');
   end if;
   if :new.direction_1 is null then
     raise_application_error(-20070,'Empty direction!');
   end if;
   if :new.cell_dest_sname is null then
     raise_application_error(-20070,'Empty cell_dest_sname!');
   end if;

   for tt in (select cell.track_npp, command_rp_id, command_inner_id, command_inner_assigned_id, 
                cell.id cell_id, r.repository_part_id, sh.track_id, r.state robot_state,
                num_of_robots nor
              from robot r, cell, shelving sh, repository_part rp
              where r.id=:new.robot_id
                    and sname=:new.cell_dest_sname
                    and sh.id=shelving_id
                    and rp.id=r.repository_part_id
                    and cell.repository_part_id=r.repository_part_id ) loop
     if nvl(tt.robot_state,0)<>0 then
       raise_application_error(-20070,'Robot must be free and ready!');
     end if;
     if nvl(tt.command_rp_id,0)<>0 then
       raise_application_error(-20070,'command_rp_id must be 0!');
     end if;
     if nvl(tt.command_inner_id,0)<>0 then
       raise_application_error(-20070,'command_inner_id must be 0!');
     end if;
     if nvl(tt.command_inner_assigned_id,0)<>0 then
       raise_application_error(-20070,'command_inner_assigned_id must be 0!');
     end if;
     if tt.nor>1 and obj_rpart.is_poss_to_lock(:new.robot_id, tt.track_npp, :new.direction_1)<>1 then
       raise_application_error(-20070,'Impossible to lock to track_dest '||tt.track_npp||'!');
     end if;
     for ci in (select * from command_inner where robot_id=:new.robot_id and state in (0,1)) loop
       raise_application_error(-20070,'There is cmd_inner id='||ci.id||' for robot!');
     end loop;
     :new.rp_id:=tt.repository_part_id;
     :new.cell_dest_id:=tt.cell_id;
     :new.cell_src_sname:='-';
     :new.priority:=1;
     :new.command_id:=-1;
     if tt.nor>1 then
       --cnt:=manager.try_to_lock(:new.robot_id, tt.track_npp, :new.direction_1,:new.id);
       cnt:= obj_rpart.Try_Track_Lock(:new.robot_id, tt.track_npp, :new.direction_1, true, rbr);

       if cnt<>tt.track_id then
         raise_application_error(-20070,'Try_to_lock bad answer '||cnt||'!');
       end if;
     end if;
     obj_robot.Set_Command_Inner(:new.robot_id, :new.id, 1, 6, :new.direction_1, Null,
                                       :new.cell_dest_sname,'MOVE '||:new.cell_dest_sname||';'||obj_rpart.Get_Cmd_Dir_Text(:new.direction_1));
     /*manager.set_command(:new.robot_id, :new.id, 1, 6, :new.direction_1, Null,
                                       :new.cell_dest_sname,
                                       'MOVE '||:new.cell_dest_sname||';'||manager.get_cmd_dir_text(:new.direction_1));   */

   end loop;
 end if;
END;
/
