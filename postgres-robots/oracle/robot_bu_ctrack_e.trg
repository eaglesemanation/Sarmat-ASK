CREATE OR REPLACE TRIGGER robot_bu_ctrack_e
BEFORE update of current_track_id
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 --dir number;
 npp1 number;
 npp2 number;
 npp_to number;
 npp_to_id number;
 cirec command_inner%rowtype;
 errm varchar2(400); 
BEGIN
 obj_robot.log(:new.id,'триггер robot_bu_ctrack_e, :old.current_track_id='||:old.current_track_id ||' :new.current_track_id='||:new.current_track_id);
 for rit in (select * from robot_trigger_ignore  where robot_id=:new.id)  loop
   return;
 end loop ;

 -- проверяем для складов с двумя роботами, а может ли робот находиться тут
 if nvl(:old.current_track_id,0)<>nvl(:new.current_track_id,0) then
   for rp in (select num_of_robots nor from repository_part where id=:new.repository_part_id) loop
     if rp.nor=2 then
       for st in (select * from track where id=:new.current_track_id and locked_by_robot_id<>:new.id) loop
         errm:='Robot '||:new.id||' is on invalid track npp '||obj_rpart.get_track_npp_by_id(:new.Current_track_id)||' old npp was '||obj_rpart.get_track_npp_by_id(:old.Current_track_id);
         obj_robot.log(:new.id,' тrbtr '||errm);
         raise_application_error(-20123, errm);
       end loop;
     end if;  
   end loop;
 end if;
 obj_robot.log(:new.id,' тrbtr '||' проверка прошла');
  
 -- снимаем блокировки
 if :old.current_track_id is not null then -- не начало работы
    obj_robot.log(:new.id,' тrbtr '||'   не начало работы, снимаем блокировки');
    select npp into npp1 from track where id=:old.current_track_id; 
    obj_robot.log(:new.id,' тrbtr '||'   npp1='||npp1);
    obj_robot.log(:new.id,' тrbtr '||'   :new.current_track_id='||:new.current_track_id);
    select npp into npp2 from track where id=:new.current_track_id;
    obj_robot.log(:new.id,' тrbtr '||'   npp2='||npp2);

    if nvl(:new.current_track_id,0)<>nvl(:OLD.current_track_id,0) then
      obj_robot.log(:new.id,' тrbtr '||'   триггер robot_bu_ctrack_e - сменили трек с '|| npp1 ||' на '||npp2||' у робота '||:new.id);
      insert into log (action, old_value, new_value, comments, robot_id, command_id )
      values(39,npp1,npp2,' тrbtr '||'триггер robot_bu_ctrack_e - сменили трек с '|| npp1 ||' на '||npp2||' у робота '||:new.id,:new.id,:new.command_inner_id );
    end if;
    obj_robot.log(:new.id,' тrbtr '||'   :new.command_inner_id= '||:new.command_inner_id);
    if nvl(:new.command_inner_id,0)<>0 and nvl(:new.wait_for_problem_resolve,0)=0 then
      select * into cirec from command_inner where id=:new.command_inner_id;
      if cirec.command_type_id in (4,21) then 
        npp_to:=cirec.npp_src;
        npp_to_id:=cirec.track_src_id;
      else
        npp_to:=cirec.npp_dest;
        npp_to_id:=cirec.track_dest_id;
      end if;
      if npp_to=cirec.track_npp_begin then
        -- начальный трек команды совпадает с конечным, никуда двигаться не надо
        obj_robot.Log(:new.id,' тrbtr  начальный трек команды совпадает с конечным');
        :new.current_track_id:=:old.current_track_id;
      else
        -- начальный трек команды и конечный - разные, надо дальше анализировать
        if  obj_rpart.is_track_between(npp2,cirec.track_npp_begin ,npp_to , cirec.direction, :new.repository_part_id)=1 then
          -- трек, где сейчас робот, между начальным и целевым, 
          -- но еще надо проверить, а не обратный ли отскок
          if  obj_rpart.is_track_between(npp2,cirec.track_npp_begin ,npp1 , cirec.direction, :new.repository_part_id)=1 then
            -- обратный отскок елы палы
            obj_robot.Log(:new.id,' тrbtr обратный отскок ');
            :new.current_track_id:=:old.current_track_id;
            npp2:=npp1;  
          end if;
        else
            -- промахнулись, разблокируем только часть правильную
            obj_robot.Log(:new.id,' тrbtr промахнулись, разблокируем только часть правильную ');
            :new.current_track_id:=npp_to_id;
            npp2:=npp_to;  
        end if;
        obj_robot.Log(:new.id,' тrbtr '||'Разблокируем трек '||npp1||' '||npp2||' '||cirec.direction);
        --manager.unlock_track(npp1,npp2,cirec.direction,:new.id,:new.repository_part_id);
        obj_rpart.unlock_track(:new.id,:new.repository_part_id, npp1,npp2,cirec.direction);
      end if;  
    end if;
 end if;
 if nvl(:new.current_track_id,0)<>0 AND nvl(:new.current_track_id,0)<>nvl(:OLD.current_track_id,0) then
   obj_robot.log(:new.id,' тrbtr '||'   смена трека');
   select npp into :new.current_track_npp from track where id=:new.current_track_id;
   :new.old_cur_track_npp:=:old.current_track_npp;
   :new.old_cur_date_time:=:new.last_access_date_time ;
   :new.last_access_date_time:=sysdate;
 end if;

 obj_robot.log(:new.id,' тrbtr '||'    итого новый :new.current_track_id='||:new.current_track_id);


END;
/
