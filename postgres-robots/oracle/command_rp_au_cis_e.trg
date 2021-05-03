create or replace trigger command_rp_au_cis_e
after update of command_inner_executed
ON command_rp
declare
  crec command_rp%rowtype;
begin
 for tc in (select * from tmp_cmd_rp order by id) loop
     select * into crec from command_rp where id=tc.id;
     if crec.is_to_free=0 then
       service.log2file('  триггер command_rp_au_cis_e - продолжаем завершение command_rp command_rp_executed='||crec.id);
       update command 
       set command_rp_executed=crec.id , crp_cell=crec.cell_dest_sname,
           error_code_id=crec.error_code_id  
       where id=crec.command_id;
     end if;  
     update robot set command_rp_id=0 where id=crec.robot_id;
     delete from tmp_cmd_rp where id=tc.id;
 end loop;

end;
/
