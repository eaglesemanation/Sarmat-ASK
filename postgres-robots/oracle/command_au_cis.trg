create or replace trigger command_au_cis
after update of command_rp_executed
ON command
declare
 crec command%rowtype;
 sumq number;
 sumqr number;
 cgid number;
 cdn varchar2(100);
 cnt number;
 crp_id number;
BEGIN
 -- для межскладских передач
 for tc in (select * from tmp_cmd where action=1 order by id) loop
     service.log2file(' trigger command_au_cis: Between repository_part transfer begin tmp.id='||tc.id);
     select * into crec from command where id=tc.id;
     service.log2file(' trigger command_au_cis: crec.id='||crec.id);
     select count(*) into cnt from command_rp where command_id=crec.id and state=5;
     service.log2file(' trigger command_au_cis: cnt='||cnt);
     if cnt>1 then
       for bc in (select * from command_rp where command_id=crec.id and state=5) loop
         service.log2file('     command_au_cis: crp.id='||bc.id);
       end loop;
     end if;
     select max(id) into crp_id from command_rp where command_id=crec.id and state=5;
     service.log2file('     command_au_cis: max crp.id='||crp_id);
     select cell_dest_sname into cdn from command_rp where command_id=crec.id and state=5 and id=crp_id;
     insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname, priority, state, command_id,
                   track_src_id , track_dest_id , npp_src, npp_dest,
                   cell_dest_id, cell_src_id, container_id)
     values (3,crec.rp_dest_id,crec.crp_cell, crec.cell_dest_sname, crec.priority, 1, crec.id,
                   obj_rpart.get_track_id_by_cell_and_rp(crec.rp_dest_id,crec.crp_cell),
                   obj_rpart.get_track_id_by_cell_and_rp(crec.rp_dest_id, crec.cell_dest_sname),
                   obj_rpart.get_track_npp_by_cell_and_rp(crec.rp_dest_id, crec.crp_cell),
                   obj_rpart.get_track_npp_by_cell_and_rp(crec.rp_dest_id, crec.cell_dest_sname),
                   obj_rpart.get_cell_id_by_name(crec.rp_dest_id,crec.cell_dest_sname),
                   obj_rpart.get_cell_id_by_name(crec.rp_dest_id,cdn),
                   crec.container_id);
     delete from tmp_cmd where id=tc.id and action=1;
 end loop;

 -- для определения не выполнена ли Command_gas полностью
 for tc in (select * from tmp_cmd where action=3 order by id) loop
   begin
     select command_gas_id into cgid from command where id=tc.id;
     select sum(quantity_to_pick) into sumq
     from command_gas_out_container_plan cp,  command_gas_out_container c
     where cp.cmd_gas_id = c.cmd_gas_id and c.cmd_gas_id=cgid
     and cp.container_id=c.container_id;
     --select sum(quantity) into sumq from command_gas_out_container where cmd_gas_id = cgid;
     select quantity into sumqr from command_gas where id=cgid;
     service.log2file(' trigger command_au_cis: правим quantity_out='||sumq||' у cg_cmd='||cgid);
     update command_gas set quantity_out=sumq where id=cgid;
     if sumq>=sumqr then
       service.log2file(' trigger command_au_cis: правим state=5 у cg_cmd='||cgid);
       update command_gas set state=5 where id=cgid;
     end if;
   exception when others then
     null;
   end;
   delete from tmp_cmd where id=tc.id and action=3;
 end loop;

 -- для внтурискладских передач
 for tc in (select * from tmp_cmd where action=5 order by id) loop
     service.log2file(' trigger command_au_cis: inner repository_part transfer begin tmp.id='||tc.id);
     select * into crec from command where id=tc.id;
     service.log2file(' trigger command_au_cis: crec.id='||crec.id);
     for cl in (select cell.*, track_id from cell, shelving sh
                where cell.id=crec.cell_dest_id and sh.id=shelving_id) loop
       for ct in (select cell.*, track_id from cell , shelving sh
                  where sname=crec.crp_cell and cell.repository_part_id=cl.repository_part_id
                   and sh.id=shelving_id) loop
         insert into command_rp (command_type_id, rp_id, cell_src_sname, cell_dest_sname, 
                       priority, state, command_id,
                       track_src_id , track_dest_id , npp_src, npp_dest,
                       cell_src_id, cell_dest_id, container_id)
         values (3,crec.rp_dest_id,crec.crp_cell, crec.cell_dest_sname, 
                       crec.priority, 1, crec.id,
                       ct.track_id, cl.track_id, ct.track_npp, cl.track_npp,
                       ct.id, cl.id, crec.container_id);
       end loop;
     end loop; 
     delete from tmp_cmd where id=tc.id and action=5;
        
 end loop;



END;
/
