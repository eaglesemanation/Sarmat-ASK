CREATE OR REPLACE TRIGGER command_bu_state_e
BEFORE update of state
ON command
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 is_ci boolean;

BEGIN
  if nvl(:old.state,0)<> nvl(:new.state,0) then
    if :new.state>=3 then
        update command_gas
        set state=1 -- начала выполняться
        where id=:new.command_gas_id and state<1;
    end if;
    if :new.state=2 and :old.state<>2 or 
       :new.state=6 and :old.state<>6 then
      for cmdrp in (select * from command_rp where command_id=:new.id) loop
        for cmdi in (select * from command_inner where command_rp_id=cmdrp.id and state not in (5,2)) loop
          if cmdi.command_type_id <> 4 then
            raise_application_error(-20123, 'It''s possible to cancel only active <Load> command!');
          end if;
          for rr in (select * from robot where nvl(command_inner_id,0)=cmdi.id) loop
            if nvl(rr.wait_for_problem_resolve ,0)=0 then
              raise_application_error(-20123, 'It''s possible to cancel command only in <wait_for_problem_resolve_state>!');
            end if;
          end loop;
          update command_inner set state=2 where command_rp_id=cmdrp.id and state not in (5,2);
          update robot set command_inner_id=null, wait_for_problem_resolve=0 where nvl(command_inner_id,0)=cmdi.id;
          update robot set command_inner_assigned_id=0 where nvl(command_inner_assigned_id,0)=cmdi.id;
        end loop;
        delete from cell_cmd_lock where  cell_id in (cmdrp.cell_src_id, cmdrp.cell_dest_id);
        update command_rp set state=2 where command_id=:new.id;
        update robot set command_rp_id=null, wait_for_problem_resolve=0 where nvl(command_rp_id,0)=cmdrp.id;
      end loop;
    end if;
  end if;
END;
/
