CREATE OR REPLACE TRIGGER cell_bu_notes_e
BEFORE update of notes
ON cell
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
  cnt number;
BEGIN
  if nvl(:new.notes,'-')<>nvl(:old.notes,'-') then
    select count(*) into cnt from command_inner 
    where :new.id in (cell_src_id, cell_dest_id) and state not in (2,5);
    if cnt>0 then
      raise_application_error (-20012, 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_inner)!');
    end if;
    select count(*) into cnt from command_rp
    where :new.id in (cell_src_id, cell_dest_id) and state not in (2,5);
    if cnt>0 then
      raise_application_error (-20012, 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_rp)!');
    end if;
    select count(*) into cnt from command
    where :new.id in (cell_src_id, cell_dest_id) and state not in (2,5);
    if cnt>0 then
      raise_application_error (-20012, 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command)!');
    end if;
    select count(*) into cnt from command_gas
    where :new.sname=cell_name and rp_id=:new.repository_part_id and state not in (2,5);
    if cnt>0 then
      raise_application_error (-20012, 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_gas)!');
    end if;
    select count(*) into cnt from command_order
    where :new.sname=cell_name and rp_id=:new.repository_part_id and state not in (2,5);
    if cnt>0 then
      raise_application_error (-20012, 'Нельзя менять компьютер ячейки - есть еще неотработанные команды (command_order)!');
    end if;
    
  end if;
END;
/
