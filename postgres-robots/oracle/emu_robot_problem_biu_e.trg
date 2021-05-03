CREATE OR REPLACE TRIGGER emu_robot_problem_biu_e
BEFORE INSERT or update
ON emu_robot_problem
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
  cnt number;
BEGIN
  if inserting then
    SELECT SEQ_emu.nextval INTO :new.ID FROM dual;
    :new.date_time_create:=sysdate;
  end if;

  select count (*) into cnt from emu_robot_problem_tttype where id=:new.tttype_id;
  if cnt=0 then
    raise_application_error(-20123, 'Обязательно указать тип начала формирования проблемы!');
  end if;

  select count (*) into cnt from emu_robot_problem_type where id=:new.type_id;
  if cnt=0 then
    raise_application_error(-20123, 'Обязательно указать тип проблемы!');
  end if;

  for ttt in (select * from emu_robot_problem_tttype where id=:new.tttype_id ) loop
    if ttt.need_rstate=1 then
      if :new.rstate_trigger is null then
        raise_application_error(-20123, 'Для данного типа проблемы обязательно указать состояние робота!');
      end if;
    end if;
    if ttt.may_cmd=0 then
      if not :new.cmd_trigger is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя задавать текст команды!');
      end if;
    end if;
    if ttt.may_date_time_begin=0 then
      if not :new.date_time_begin  is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя задавать дату-время!');
      end if;
    end if;
    if ttt.may_track_npp =0 then
      if not :new.track_npp_trigger   is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя задавать № трека для условия!');
      end if;
    end if;
  end loop;

  for t in (select * from emu_robot_problem_type where id=:new.type_id ) loop
    if t.need_error_code=1 then
      if :new.error_code is null then
        raise_application_error(-20123, 'Для данного типа проблемы требуется код ошибки!');
      end if;
    end if;
    if t.need_error_msg=1 then
      if :new.error_msg  is null then
        raise_application_error(-20123, 'Для данного типа проблемы требуется текст ошибки!');
      end if;
    end if;
    if t.may_be_cmd_current=0 then
      if not :new.cmd_current  is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя указывать значение текущей команды!');
      end if;
    end if;
    if t.need_robot_state=1 then
      if :new.set_robot_state   is null then
        raise_application_error(-20123, 'Для данного типа проблемы требуется состояние робота!');
      end if;
    end if;
    if t.need_platform_busy=1 then
      if :new.set_platform_busy is null then
        raise_application_error(-20123, 'Для данного типа проблемы требуется состояние платформы!');
      end if;
    end if;
    if t.may_track_npp=0 then
      if not :new.set_track_npp  is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя указывать задаваемое значение секции!');
      end if;
    end if;
    if t.may_cmd_answer=0 then
      if not :new.set_cmd_answer   is null then
        raise_application_error(-20123, 'Для данного типа проблемы нельзя указывать задаваемое значение ответа на команду!');
      end if;
    end if;
  end loop;

END;
/
