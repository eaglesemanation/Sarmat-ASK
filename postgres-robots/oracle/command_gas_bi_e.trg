CREATE OR REPLACE TRIGGER command_gas_bi_e
BEFORE INSERT
ON command_gas
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 error_name varchar2(250);
 s varchar2(4000);
 ss varchar2(4000);
 scnt number;
 scnt2 number;
 sgd varchar2(40);
 sn varchar2(4000);
 snotes varchar2(4000);
 cell_id_ number;
 cell_dest_id_ number;
 container_id_ number;
 cnt_type number;
 rp_S_id number;
 rpt number;
 cell_sname_ varchar2(100);
 wf number;
 wcnt_id number;
 cc_id_ number;
 scheck number;
 cnt_id number;
 cmgd number;
 qty_rest number;
 qty_need number;
 qty_by_cc number;
 sb_firm number;
 is_party_c number;
 fullness number;
 icasc number;
 lloc number;
 gd_id_ number;
 gdp_id__ number;
 IAEC number;
 new_rp_id number;
 all_is_ok boolean;
 csnpp number;
 csorient varchar2(1);
 maxnpp number;
 pri_ number;
BEGIN
 :new.user_name:=user;
 :new.state_ind:=:new.state;

 if :new.ID is null then
   SELECT SEQ_command_gas.nextval INTO :new.ID FROM dual;
   :new.date_time_create:=sysdate;
   :new.time_create:=systimestamp;
 end if;
 select container_multi_gd, storage_by_firm, is_cell_accept_strong_check, is_party_calc, is_allow_store_empty_CNT
 into cmgd, sb_firm, icasc, is_party_c, IAEC
 from repository;

 ------------------------------------------------------
 -- проверки, в случае, если без рабочего стола работа
 ------------------------------------------------------
 for rp in (select * from repository where nvl(is_allow_desktop,0)=0)  loop
   if :new.COMMAND_TYPE_ID in (12,27,11,14) then
     obj_doc_expense.check_last_doc_end(:new.pri_doc_number);
   end if;
 end loop;

 --------------------------
 -- GoodDesc.AddInfo
 --------------------------
 if :new.COMMAND_TYPE_ID=10 then
   if :new.good_desc_id is null then
     raise_application_error(-20070,'Good_desc_id must be not Null!');
   end if;
   if :new.ABC_RANG is null then
     raise_application_error(-20070,'ABC_RANG must be not Null!');
   end if;
   select count(*) into cnt from good_desc
   where id=:new.good_desc_id;
   if cnt=0 then
     -- добавляем
     insert into good_desc (id, name, mass_1, mass_box, quantity_box, abc_rang)
     values(:new.good_desc_id,:new.Good_desc_name,:new.Mass_1,:new.Mass_box, :new.quantity_box, :new.abc_rang);
   else
     -- обновляем
     update good_desc
     set
       name=:new.Good_desc_name,
       mass_1=:new.mass_1,
       mass_box=:new.mass_box,
       quantity_box=:new.quantity_box,
       abc_rang=:new.abc_rang,
       cubage=:new.cubage,
       max_pack=:new.max_pack,
       sc_t=:new.sc_t,
       rc_t=:new.rc_t
     where id=:new.good_desc_id;
   end if;
   :new.state:=5;
   :new.state_ind:=:new.state;

 --------------------------
 -- Container.Accept
 --------------------------
 elsif :new.COMMAND_TYPE_ID=11 then
   if nvl(:new.container_id,0)<>0 then
     begin
       select barcode into :new.CONTAINER_BARCODE from container where id=:new.container_id;
     exception when others then
       insert into container (id,barcode, type, location, cell_id)
       values(:new.container_id,:new.container_barcode,nvl(:new.container_type,0),0, :new.cell_id)
       returning id into container_id_;
     end;
   end if;
   if nvl(:new.cell_id,0)<>0 then
     select sname, repository_part_id into  :new.cell_name, :new.rp_id
     from cell where id=:new.cell_id;
   end if;

   -- проверка на не NULL
   if :new.CONTAINER_BARCODE is null then
     raise_application_error(-20070,'CONTAINER_BARCODE must be not Null!');
   end if;
   if :new.content  is null and IAEC<>1 then
     raise_application_error(-20070,'content must be not Null!');
   end if;
   --raise_application_error(-20070,length(:new.content)||' '||:new.content);
   service.log2file('Container.Accept '||:new.content);
   -- проверка на фирму
   if sb_firm=1 and nvl(:new.firm_id,0)=0 then
     raise_application_error(-20070,'firm must be not Null!');
   end if;
   -- склад по умолчанию
   if :new.rp_id  is null then
     select count(*) into cnt from repository_part rp  where purpose_id in (1,3);
     if cnt=1 then
       select id into :new.rp_id from repository_part rp  where purpose_id in (1,3);
     else
       raise_application_error(-20070,'<rp_id> must be assigned!');
     end if;
   end if;
   -- проверка на № документа
   for rr in (select name from repository where nvl(IS_STRONG_PRIHOD_CHECK,0)=1) loop
     if :new.pri_doc_number is null then
       raise_application_error(-20070,'Strong Check is ON on repository! Need debit document number!');
     end if;
   end loop;
   -- ячейка по умолчанию
   if :new.cell_name   is null then
     select count(*) into cnt from cell
     where repository_part_id=:new.rp_id and hi_level_type in (9,15,16) and is_error<>1;
     if cnt=1 then
       select sname into :new.cell_name from cell
       where repository_part_id=:new.rp_id and hi_level_type in (9,15,16) and is_error<>1;
     else
       raise_application_error(-20070,'cell_name  must be not Null!');
     end if;
   end if;
   -- определяем ячейку
   if :new.cell_name='Desktop' then
     -- тут у нас вариант тупо на рабочий стол положили для дальнейшей ратботы
     if :new.content  is null then
       raise_application_error(-20070,'content must be not Null!');
     end if;
     lloc:=0;
     Null;
   else
     lloc:=1;

     select count(*) into cnt from cell
     where repository_part_id=:new.rp_id and sname=:new.cell_name;
     if cnt=0 then
       raise_application_error(-20070,'bad <cell_name> or <rp_id>!');
     else
       select id, container_id, is_full into cell_id_, wcnt_id, fullness
       from cell
       where repository_part_id=:new.rp_id and sname=:new.cell_name;
     end if;
     for co in (select * from cell where id=cell_id_) loop
       if co.hi_level_type not in (15,9,14,16) or co.is_error=1 then
         raise_application_error(-20070,'The cell '||:new.cell_name||' is bad type or error type!');
       end if;
     end loop;
   end if;

   if nvl(:new.cell_name,'-')<>'Desktop' then
     -- проверяем, а есть ли свободные ячейки
     select count(*) into cnt from
     (select 1 from dual where exists (select * from cell c where hi_level_type=1 and is_full=0
      and is_error=0 and service.is_cell_cmd_locked(c.id)=0));
     if cnt=0 then
       raise_application_error(-20070,'The repository is overload (Desktop)!');
     end if;
     -- в случае строгой проверки проверяем, а свободна ли ячейка
     if icasc=1 then
       select is_full into cnt from cell where id=cell_id_;
       if cnt>0 then
         raise_application_error(-20070,'The cell <'||:new.cell_name||'> in rp '||:new.rp_id||' is full!');
       end if;
     end if;
     --  проверяем, а не насували ли команд кладовщики
     select count(*) into cnt from command_gas cg
     where state=1 and rp_id=:new.rp_id and cell_name=:new.cell_name
           and command_type_id=:new.command_type_id
           and not exists (select * from command where command_gas_id=cg.id);
     if cnt>0 then
          raise_application_error(-20070,'Command buffer for cell '||:new.cell_name||' is overload! Cnt='||cnt);
     end if;
     -- проверяем, а не лежит ли в ячейке контейнер с команды, иной чем прием товара
     if fullness>0 and nvl(wcnt_id,0)<>0 then -- уже лежит какой-то контейнер в той ячейке, куда ложим
       for cgcnt in (select * from command_gas where container_barcode=
                                                     (select barcode from container where id=wcnt_id)
                                                     and command_type_id in (14,12,18,11)
                     order by id desc) loop
         if cgcnt.command_type_id in (14,12) then
           select barcode into s from container where id=wcnt_id;
           raise_application_error(-20070,'Cell '||:new.cell_name||' is busy by another container '||s||'!');
         end if;
         exit;
       end loop;
     end if;
     -- проверяем, а не идет ли в ячейку товар по командам
     for cb in (select * from cell_cmd_lock  where cell_id=cell_id_) loop
       for cmd in (select cg.* from command c, command_gas cg where c.command_gas_id=cg.id and c.id=cb.cmd_id) loop
         if cmd.command_type_id in (14,12)  then
           raise_application_error(-20070,'Cell '||:new.cell_name||' is blocked by another command '||cb.cmd_id||'!');
         end if;
       end loop;
     end loop;
   end if;

   -- ищем контейнер
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then -- нет контейнера
     select strong_container_check into scheck from repository;
     if scheck=1 then -- строгая проверка
        raise_application_error(-20070,'Container '||:new.CONTAINER_BARCODE||' is not registrated in system!');
     end if;
     insert into container (barcode, type, location, cell_id, firm_id)
     values(:new.container_barcode,nvl(:new.container_type,0),lloc, cell_id_, :new.firm_id )
     returning id into container_id_;
   else
     select count(*) into cnt from container
     where barcode=:new.container_barcode and location=1;
     if cnt<>0 then
        raise_application_error(-20070,'Container is already in repository!');
     end if;
     select count(*) into cnt from command_gas
     where container_barcode=:new.container_barcode and state in (1,3) and id<>:new.id;
     if cnt<>0 then
        raise_application_error(-20070,'Container is already in work!');
     end if;
     select id into container_id_ from container where barcode=:new.container_barcode;
     delete from container_content where container_id=container_id_;
     update container set cell_id=cell_id_ , firm_id=:new.firm_id
     where id=container_id_;
   end if;
   :new.container_id:=container_id_;

   -- проверяем, а не дадена ли уже команда на возврат из этой же ячейки
   for cmd_ret in (select * from command_gas where command_type_id=18 and rp_id=:new.rp_id and :new.cell_name=cell_name and state=0) loop
        raise_application_error(-20070,'Commad conflict found!');
   end loop;

   -- проверяем что есть место
   if obj_ask.is_enable_container_accept(:new.rp_id,:new.container_id)=0 then
        raise_application_error(-20070,'Repository overload!');
   end if;

   -- заполненность контейнера прописываем
   if :new.container_fullness is not null then
     if not (:new.container_fullness between 0 and 1 ) then
       raise_application_error(-20070,'Container fullness must be between 0 and 1!');
     end if;
     update container set fullness=:new.container_fullness where id=container_id_;
   end if;
   -- название контейнера
   if :new.notes is not null then
     update container set notes=:new.notes
     where id=container_id_;
   end if;
   -- check is opened container collection
    select count(*) into cnt from container_collection
    where state=0 and container_id=:new.container_id;
    if cnt<>0 then
      raise_application_error (-20003, 'Container collection on container '||:new.container_barcode||' is still opened!', TRUE);
    end if;

   -- а есть ли место
   select type into cnt from container where id=:new.container_id;
   if obj_rpart.has_free_cell(cnt)=0 then
      raise_application_error (-20003, service.ml_get_rus_eng_val('Склад переполнен! Мест нет!', 'Repository is overload (by type)! ')||cnt, TRUE);
   end if;

   -- разбор строки состава принимаемого контейнера
   if :new.content is not null then
     obj_cmd_gas.parse_cg_cc(:new.id, :new.content, cmgd );
     select count(*) into cnt
     from
       command_gas_container_content cgcc
     where command_gas_id=:new.id and gdp_id is not null and
           not exists (select * from gd_party gdp, good_desc gd where cgcc.gdp_id=gdp.id and cgcc.gd_id=gd.id and gd.good_desc_id=gdp.gd_id);
     if cnt>0 then
        raise_application_error (-20003, 'Part No is bad!', TRUE);
     end if;
   end if;

   if is_party_c=1 then
     -- хитрое добавление состава контейнера для партий
     insert into container_content (container_id, good_desc_id, quantity, notes, gdp_id)
     select container_id_,gd_id,qty,notes, gdp_id
     from command_gas_container_content where command_gas_id=:new.id and nvl(gdp_id,0)<>0;

     -- добавляем пустые партии
     insert into gd_party (pname, gd_id)
     select null, gd.good_desc_id
     from command_gas_container_content cgcc, good_desc gd
     where command_gas_id=:new.id and cgcc.gd_id=gd.id and nvl(gdp_id,0)=0 and not exists (select * from gd_party where pname is null and gd_id=gd.good_desc_id);
     update command_gas_container_content cgu
     set gdp_id=(select id from gd_party where gd_id=(select good_desc_id from good_desc where id=cgu.gd_id) and pname is null)
     where command_gas_id=:new.id and gdp_id is null;

     insert into container_content (container_id, good_desc_id, quantity, notes, gdp_id)
     select container_id_,gd_id,qty,notes, (select id from gd_party where pname is null and gd_id=(select good_desc_id from good_desc where id=cgcc.gd_id))
     from command_gas_container_content cgcc where command_gas_id=:new.id and nvl(gdp_id,0)<>0;
   else
     insert into container_content (container_id, good_desc_id, quantity, notes, gdp_id)
     select container_id_,gd_id,qty,notes, gdp_id
     from command_gas_container_content where command_gas_id=:new.id;
   end if;

   :new.container_cell_name:=:new.cell_name;
   :new.container_rp_id:=:new.rp_id;

   if nvl(:new.cell_name, '-')='Desktop' then -- на рабочий стол ложим
     :new.state:=5;
     :new.state_ind:=:new.state;

     for ccgd in (select cc.*, gd.good_desc_id gdid_ from container_content cc, good_desc gd where cc.container_id=:new.container_id and cc.good_desc_id=gd.id) loop

       if sb_firm=1 then -- учет товаров по фирме
         begin
           INSERT into firm_gd (firm_id, gd_id, quantity)
           values(:new.firm_id,ccgd.good_desc_id,ccgd.quantity);
         exception when others then
           update firm_gd set quantity=quantity+
              ccgd.quantity
           where gd_id=ccgd.good_desc_id and firm_id=:new.firm_id;
         end;

       elsif nvl(is_party_c,0)=1 then -- учет по партиям
         update gd_party
         set qty=qty+ ccgd.quantity
         where gd_id=ccgd.gdid_ and (pname is null and nvl(ccgd.gdp_id,0)=0 or ccgd.gdp_id=id);

         -- триггер не срабатывает из триггера, сука!
         /*update good_desc set quantity=quantity+
            ccgd.quantity
         where id=ccgd.good_desc_id;*/


       else -- общий учет товаров
         update good_desc set quantity=quantity+
            ccgd.quantity
         where id=ccgd.good_desc_id;
       end if;
     end loop;
     insert into container_collection (container_id, state, cmd_gas_id, container_barcode)
     values (:new.container_id,0,:new.id,:new.container_barcode);

   else -- реальный прием
     :new.state:=0;
     :new.state_ind:=:new.state;

   end if;

   for rr in (select name from repository where nvl(IS_STRONG_PRIHOD_CHECK,0)=1) loop
     -- триггер на автообновление статусов приходных накладных
     insert into tmp_cmd_gas(cmd_gas_id, action ) values(:new.id,1);
     obj_doc_expense.strong_pri_check(:new.id, :new.pri_doc_number);
   end loop;


 --------------------------
 -- Good.Out
 --------------------------
 elsif :new.COMMAND_TYPE_ID=12 then
   if nvl(:new.good_desc_id,'-')='-' then
     raise_application_error(-20070,'<Good_desc_id> must be not null!');
   end if;
   select count(*) into cnt  from good_desc where id=:new.good_desc_id;
   if cnt=0 then
     raise_application_error(-20070,'<Good_desc_id> not found in database!');
   end if;
   -- проверка на фирму
   if sb_firm=1 and nvl(:new.firm_id,0)=0 then
     raise_application_error(-20070,'firm must be not Null!');
   end if;
   -- склад по умолчанию
   if nvl(:new.rp_id,0)=0 then
     select count(*) into cnt from repository_part rp  where purpose_id in (2,3);
     if cnt=1 then
       select id into :new.rp_id from repository_part rp  where purpose_id in (2,3);
     else
       raise_application_error(-20070,'<rp_id> must be assigned!');
     end if;
   end if;
   -- партии проверяем
   if :new.gd_party_id is not null then
     select count(*)  into cnt from good_desc gd, gd_party gdp where gd.id=:new.good_desc_id and gd.good_desc_id=gdp.gd_id and gdp.id=:new.gd_party_id;
     if cnt=0 then
       raise_application_error(-20070,'Pointed shipment is not exists for current good card!');
     end if;
   end if;
   -- ячейки сброса по умолчанию
   if :new.cell_name is null then
     for csb in (select * from cell where is_error=0 and repository_part_id=:new.rp_id
                 and hi_level_type in(12,15)) loop
       if :new.cell_name is null then
         :new.cell_name:=csb.sname;
       else
         :new.cell_name:=:new.cell_name||','||csb.sname;
       end if;
     end loop;
   end if;
   -- конкретные ячейки сброса
   sn:=:new.cell_name;
   delete from command_gas_cell_in where command_gas_id=:new.id;
   loop
     cnt:=instr(sn,',');
     if cnt<>0 then
       s:=trim(substr(sn,1,cnt-1));
       sn:=trim(substr(sn,cnt+1));
     else
       s:=trim(sn);
       sn:=null;
     end if;
     select count(*) into cnt from cell where sname=s and repository_part_id=:new.rp_id;
     if cnt=0 then
       raise_application_error(-20070,'<'||s||'> as cell is not exists!');
     end if;
     insert into command_gas_cell_in (command_gas_id, cell_id, sname, track_npp)
     select :new.id, id, sname,track_npp
     from cell where sname=s and repository_part_id=:new.rp_id;
     exit when sn is null;
     --:new.state:=1; -- как примем, тогда и назначим
   end loop;

 --------------------------
 -- Container.Remove
 --------------------------
 elsif :new.COMMAND_TYPE_ID=13 then
   service.log2file('  команда Container.Remove box='||:new.CONTAINER_BARCODE||'; cmd_type='||:new.command_type_id);
   if nvl(:new.container_id,0)<>0 then
     select barcode into :new.CONTAINER_BARCODE from container where id=:new.container_id;
   end if;
   :new.container_barcode:=trim(:new.container_barcode);
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
   end if;
   select count(*) into cnt from container where barcode=:new.container_barcode and location =1;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> is not in cell!');
   end if;
   select id into :new.container_id from container where barcode=:new.container_barcode;
   select cell_id into cell_id_ from container where barcode=:new.container_barcode;
   -- проверяем, а можно ли вообще из этой ячейки делать изъятие
   select hi_level_type into cnt from cell where id=cell_id_;
   if cnt in (16,14,9) then
     raise_application_error(-20071,'Operation Container.Remove is forbiden for this cell type!');
   end if;
   -- проверяем, а нет ли в процессе команды возврата
   select count(*) into cnt from command_gas cg
   where state in (0,1,3) and container_id=:new.container_id and command_type_id=18;
   if cnt>0 then
     raise_application_error(-20071,'Container with barcode <'||:new.container_barcode||'> is in return command processing!');
   end if;
   insert into shelving_need_to_redraw (shelving_id)
   select shelving_id from cell where id=cell_id_;
   update container set location=0 where barcode=:new.container_barcode;
   update cell
   set is_full=is_full-1
   where id=cell_id_;
   update cell
   set container_id=0
   where id=cell_id_ and is_full=0;
   select nvl(sum(quantity),0) into cnt from container_content where container_id =:new.container_id;
   if cnt>0 then -- есть ненулевой товар
     select count(*) into cnt from container_collection where container_id=:new.container_id and state=0;
     if cnt=0 then -- нет открытого отбора-коллекции, добавляем
       insert into container_collection (container_id,container_barcode,state,cmd_gas_id )
       values(:new.container_id,:new.container_barcode,0,:new.id);
     end if;
   end if;
   :new.state:=5;
   :new.state_ind:=:new.state;


 --------------------------
 -- Container.Transfer
 --------------------------
 elsif :new.COMMAND_TYPE_ID=14 then
   if nvl(:new.container_id,0)<>0 then
     select barcode into :new.CONTAINER_BARCODE from container where id=:new.container_id;
   end if;
   if nvl(:new.cell_id,0)<>0 then
     select sname, repository_part_id into  :new.cell_name, :new.rp_id
     from cell where id=:new.cell_id;
   end if;

   :new.container_barcode:=trim(:new.container_barcode);
   if nvl(:new.rp_id,0)=0 then
     select count(*) into cnt from repository_part;
     if cnt>1 then
       raise_application_error(-20070,'You need to define repository_part_id!');
     else
       select id into :new.rp_id from repository_part;
     end if;

   end if;
   -- ячейку - приемник проверяем
   if :new.cell_name is null then
      -- вначале ищем, а нет ли автоматом назначить
      for cc in (select * from cell where repository_part_id=:new.rp_id and is_full=0 and hi_level_type=12 and service.is_cell_over_locked(cell.id)=0) loop
        :new.cell_name:=cc.sname;
      end loop;
      if :new.cell_name is null then
        raise_application_error(-20070,'cell_name  must be not Null!');
      end if;
   end if;
   :new.cell_name:=trim(:new.cell_name);
   select count(*) into cnt from cell
   where repository_part_id=:new.rp_id and sname=:new.cell_name;
   if cnt=0 then
      raise_application_error(-20070,'cell_name '||trim(:new.cell_name)||' doesnt exists!');
   end if;
   for cc in (select *  from cell where repository_part_id=:new.rp_id and sname=:new.cell_name) loop
     if obj_rpart.is_cell_locked_by_repaire(cc.id)=1 then
       raise_application_error(-20070,'cell_name '||trim(:new.cell_name)||' is locked by repaire robot!');
     end if;
   end loop;
   select count(*) into cnt from cell
   where repository_part_id=:new.rp_id and sname=trim(:new.cell_name) and is_full<max_full_size;
   if cnt=0 then
      raise_application_error(-20070,'cell_name '||trim(:new.cell_name)||' already is full!');
   end if;
   select count(*) into cnt from cell
   where repository_part_id=:new.rp_id and sname=trim(:new.cell_name) and is_error=0;
   if cnt=0 then
      raise_application_error(-20070,'cell_name '||trim(:new.cell_name)||' is error cell!');
   end if;
   select count(*) into cnt from cell
   where repository_part_id=:new.rp_id and sname=trim(:new.cell_name)
         and is_full<max_full_size and service.is_cell_over_locked(cell.id)=0;
   if cnt=0 then
      raise_application_error(-20070,service.ml_get_rus_eng_val(
              'Ячейка '||trim(:new.cell_name)||' уже блокирована другой командой! Ждите завершения операции!',
              'cell_name '||trim(:new.cell_name)||' already blocked by cmd!'));
   end if;
   select count(*) into cnt from cell
   where repository_part_id=:new.rp_id and sname=trim(:new.cell_name) and is_full<max_full_size and nvl(blocked_by_ci_id,0)=0;
   if cnt=0 then
      raise_application_error(-20070,'cell_name '||trim(:new.cell_name)||' already blocked by command inner!');
   end if;
   select track_npp, substr(nvl(orientaition,'-'),1,1) into csnpp, csorient
   from cell where repository_part_id=:new.rp_id and sname=:new.cell_name;
   select max_npp, repository_type into maxnpp , rpt
   from repository_part where id=:new.rp_id;
   -- проверяем контейнеер
   if :new.container_barcode is not null then -- ШК контейнера не пустой - реальная команда
     select count(*) into cnt from container where barcode=:new.container_barcode;
     if cnt=0 then
       raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
     end if;
     select count(*) into cnt from container where barcode=:new.container_barcode and location =1;
     if cnt=0 then
       raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> is not in cell!');
     end if;
     select cell_id, cntt.id, type , sname, c.repository_part_id
     into cell_id_, container_id_, cnt_type , cell_sname_, rp_s_id
     from container cntt, cell c
     where cntt.barcode=:new.container_barcode and c.id=cntt.cell_id;
     :new.container_id:=container_id_;
     -- проверяем ячейку-источник
     select count(*) into cnt from cell
     where id=cell_id_ and hi_level_type in (1,15,12);
     if cnt=0 then
        raise_application_error(-20070,'container '||trim(:new.container_barcode)||' is not in storage or unitype cell!');
     end if;
     if service.is_cell_cmd_locked(cell_id_)=1 then
        raise_application_error(-20070,'Source cell id='||cell_id_||' is locked by another cmd!');
     end if;
     if obj_rpart.is_cell_locked_by_repaire(cell_id_)=1 then
        raise_application_error(-20070,'Source cell id='||cell_id_||' is locked by repaire robot!');
     end if;
   else -- подвоз пустого
     :new.notes:='Подвоз пустого контейнера';
     for cntr in (select cnt.* from container cnt, cell
                  where location=1 and cell.container_id=cnt.id
                        and service.get_container_sum_qty(cnt.id)=0
                        and hi_level_type=1
                        and obj_rpart.is_cell_locked_by_repaire(cell.id)=0
                  order by abs(repository_part_id-nvl(:new.rp_id,0)),
                        obj_ask.calc_distance(rpt, maxnpp, csnpp, track_npp),
                        abs(ascii(csorient)-ascii(cell.orientaition)) desc
                        ) loop
        all_is_ok:=true;
        begin
          :new.container_barcode:=cntr.barcode;
          select cell_id, cntt.id, type , sname, c.repository_part_id
          into cell_id_, container_id_, cnt_type , cell_sname_, rp_s_id
          from container cntt, cell c
          where cntt.barcode=:new.container_barcode and c.id=cntt.cell_id;
          :new.container_id:=container_id_;
          -- проверяем ячейку-источник
          select count(*) into cnt from cell
          where id=cell_id_ and hi_level_type in (1,15,12);
          if cnt=0 then
             raise_application_error(-20070,'container '||trim(:new.container_barcode)||' is not in storage or unitype cell!');
          end if;
          if service.is_cell_cmd_locked(cell_id_)=1 then
             raise_application_error(-20070,'Source cell id='||cell_id_||' is locked by another cmd!');
          end if;
       exception when others then
          all_is_ok:=false;
       end;
       exit when all_is_ok;
     end loop;
   end if;
   -- склад по умолчанию
   if nvl(:new.rp_id,0)=0 then
     select count(*) into cnt from repository_part rp  where purpose_id  in (2,3);
     if cnt=1 then
       select id into :new.rp_id from repository_part rp  where purpose_id  in (2,3);
     else
       raise_application_error(-20070,'<rp_id> must be assigned!');
     end if;
   end if;
   if cnt_type=0 then -- проверка для больших контейнеров - не суем ли их в маленькие
     select count(*) into cnt from cell
     where repository_part_id=:new.rp_id and sname=trim(:new.cell_name)
           and is_full<max_full_size and nvl(blocked_by_ci_id,0)=0 and cell_size=0;
     if cnt=0 then
        raise_application_error(-20070,'cell '||trim(:new.cell_name)||' is too small !');
     end if;
   end if;
   -- проверяем, а не команда ли для разных складов без транзитных ячеек
   if rp_s_id<>:new.rp_id then
     select count(*) into cnt from cell where hi_level_type in (6,7,8) and repository_part_id in (rp_s_id,:new.rp_id);
     if cnt=0 then
       raise_application_error(-20070,'Repository part does''nt have transit cells!');
     end if;
   end if;
   -- проверяем, а нет ли активного автоматического сбора на эту ячейку
   for co in (select * from command_order
              where command_type_id=15 and state not in (2,5)
                and cell_name=:new.cell_name and rp_id=:new.rp_id) loop
       raise_application_error(-20070,'Уже есть активная автоматическая команда сбора для данного рабочего места. Дождитесь завершения автоматического сбора, и попробуйте снова!');
   end loop;
   -- проверяем, а не воровство ли это контейнера с другого рабочего места?
   for vrv in (select cs.* from cell cs, cell cd where cs.repository_part_id =rp_s_id and cs.sname=cell_sname_ 
                and cd.repository_part_id=:new.rp_id and cd.sname=:new.cell_name 
                and cs.hi_level_type in (15,2,3,4,5,12,14,16) and cd.hi_level_type in (15,2,3,4,5,12,14,16)) loop
       raise_application_error(-20070,'Нельзя воровать контейнеры с других рабочих мест оператора! Дождитесь, пока оператор на другом рабочем месте закончит работу!');
   end loop;

   -- даем команду таки
   obj_ask.Set_Command(:new.id,1,rp_s_id, cell_sname_,
          :new.rp_id,:new.cell_name,:new.priority, container_id_);

 --------------------------
 -- Handle.Container.Out
 --------------------------
 elsif :new.COMMAND_TYPE_ID=27 then
   :new.container_barcode:=trim(:new.container_barcode);
   -- проверяем контейнеер
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
   end if;
   select count(*) into cnt from container where barcode=:new.container_barcode and location =1;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> is not in cell!');
   end if;
   select id into :new.container_id from container where barcode=:new.container_barcode;
   select cell_id into cell_id_ from container where barcode=:new.container_barcode;
   insert into shelving_need_to_redraw (shelving_id)
   select shelving_id from cell where id=cell_id_;
   update container set location=0 where barcode=:new.container_barcode;
   update cell
   set is_full=is_full-1, container_id=0
   where id=cell_id_;
   select nvl(sum(quantity),0) into cnt from container_content where container_id =:new.container_id;
   if cnt>0 then -- есть ненулевой товар
     select count(*) into cnt from container_collection where container_id=:new.container_id and state=0;
     if cnt=0 then -- нет открытого отбора-коллекции, добавляем
       insert into container_collection (container_id,container_barcode,state,cmd_gas_id )
       values(:new.container_id,:new.container_barcode,0,:new.id);
     end if;
   end if;
   :new.state:=5;
   :new.state_ind:=:new.state;



 --------------------------
 -- Container.Content.Remove
 --------------------------
 elsif :new.COMMAND_TYPE_ID=24 then
   -- проверяем товар
   if nvl(:new.good_desc_id,'-')='-' then
     raise_application_error(-20070,'<Good_desc_id> must be not null!');
   end if;
   select count(*) into cnt  from good_desc where id=:new.good_desc_id;
   if cnt=0 then
     raise_application_error(-20070,'<Good_desc_id> not found in database!');
   end if;
   -- проверяем контейнер
   if :new.CONTAINER_BARCODE is null then
     raise_application_error(-20070,'CONTAINER_BARCODE must be not Null!');
   end if;
   :new.container_barcode:=trim(:new.container_barcode);
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
   else
     select id into :new.container_id from container where barcode=:new.container_barcode;
   end if;
   -- проверяем есть ли списываемый товар в контейнере
   select count(*) into cnt from container_content where container_id=:new.container_id and good_desc_id=:new.good_desc_id and quantity>0;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t contain good with id='||:new.good_desc_id||'!');
   end if;
   select count(*) into cnt from container_content where container_id=:new.container_id and good_desc_id=:new.good_desc_id and quantity>=:new.quantity;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t contain enough good with id='||:new.good_desc_id||'. Need to remove'||:new.quantity||'!');
   end if;
   service.log2file('  команда Container.Content.Remove box='||:new.CONTAINER_BARCODE||'; cmd_type='||:new.command_type_id||'; qty='||:new.quantity||'; good_desc_id='||:new.good_desc_id);
   -- проверяем в случае строгой проверки по документам
   for rr in (select name from repository where nvl(IS_STRONG_PRIHOD_CHECK,0)=1) loop
     if :new.quantity>obj_cmd_order.get_ras_gd_rest(:new.pri_doc_number, obj_ask.get_good_desc_id_by_id(:new.good_desc_id), :new.gd_party_id) then
       raise_application_error(-20070,'Doc with ID '||:new.pri_doc_number||' have not this qty of good!');
     end if;
   end loop;


   -- делаем действия
   -- списываем коллекцию
   qty_by_cc:=0;
   qty_rest:=:new.quantity;
   for cc in (select * from container_collection  where state=0 and container_id=:new.container_id) loop
     for ccc in (select * from container_collection_content ccc
                 where cc_id=cc.id and good_desc_id=:new.good_desc_id and (is_party_c=0 or gd_party_id=:new.gd_party_id)
                 order by cmd_order_id) loop
       qty_need:= ccc.quantity_need -ccc.quantity_real - ccc.quantity_deficit ;
       if qty_rest>=qty_need then
         qty_rest:=qty_rest-qty_need;
         qty_by_cc:=qty_by_cc+qty_need;
         update container_collection_content t set quantity_real =quantity_real+qty_need
         where cc_id=cc.id and good_desc_id=:new.good_desc_id and nvl(cmd_order_id,0)= nvl(ccc.cmd_order_id,0)
               and (is_party_c=0 or gd_party_id=:new.gd_party_id);
       else
         qty_by_cc:=qty_by_cc+qty_rest;
         update container_collection_content t set quantity_real =quantity_real+qty_rest
         where cc_id=cc.id and good_desc_id=:new.good_desc_id and nvl(cmd_order_id,0)= nvl(ccc.cmd_order_id,0)
               and (is_party_c=0 or gd_party_id=:new.gd_party_id);
         qty_rest:=0;
       end if;
     end loop;
   end loop;

   -- а теперь состав контейнера
   select count(*) into cnt from container_content
   where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=0;
   if cnt=0 then -- есть только по партиям
     if :new.gd_party_id is null then
      raise_application_error(-20070,'Shipment is not noticed!');
     end if;
     select count(*) into cnt from container_content
     where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=:new.gd_party_id;
     if cnt=0 then
      raise_application_error(-20070,'Pointed shipment is not in container!');
     end if;
     update container_content set quantity=quantity-:new.quantity
     where container_id=:new.container_id and good_desc_id=:new.good_desc_id and gdp_id=:new.gd_party_id;
   else -- есть и без партий
     if :new.gd_party_id is null then
       update container_content set quantity=quantity-:new.quantity
       where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=0;
     else -- но партия задана
       select count(*) into cnt from container_content
       where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=:new.gd_party_id;
       if cnt=0 then
        raise_application_error(-20070,'Pointed shipment is not in container!');
       end if;
       update container_content set quantity=quantity-:new.quantity
       where container_id=:new.container_id and good_desc_id=:new.good_desc_id and gdp_id=:new.gd_party_id;
     end if;
   end if;

   --raise_application_error(-20070,qty_by_cc||' '||qty_rest);
   -- и из товаров убираем
   if sb_firm=1 then
     for frm in (select firm_id id from container where id=:new.container_id) loop
         update firm_gd set quantity=quantity-(:new.quantity-qty_by_cc) where gd_id=:new.good_desc_id and firm_id=frm.id;
         update firm_gd set quantity_reserved=quantity_reserved-qty_by_cc where gd_id=:new.good_desc_id and firm_id=frm.id;
     end loop;
   elsif is_party_c=1 then
     update gd_party set qty=qty-(:new.quantity-qty_by_cc) where id=:new.gd_party_id;
     update gd_party set qty_reserved=qty_reserved-qty_by_cc where id=:new.gd_party_id;
   else
     update good_desc set quantity=quantity-(:new.quantity-qty_by_cc) where id=:new.good_desc_id;
     update good_desc set quantity_reserved=quantity_reserved-qty_by_cc where id=:new.good_desc_id;
   end if;
   -- проверякм, не обнулился ли контейнер, и если обнулился, то закрываем сбор по контейнеру
   for emp_cont in (select sum(quantity) sq from container_content where container_id=:new.container_id) loop
     if emp_cont.sq=0 then
       update container_collection set state=1 where state=0 and container_id =:new.container_id;
       update container set fullness=0 where id=:new.container_id;
     end if;
   end loop;
   :new.state:=5;
   :new.state_ind:=:new.state;

   for rr in (select name from repository where nvl(IS_STRONG_PRIHOD_CHECK,0)=1) loop
     -- проверяем расходные накладные на завершение сбора
     insert into tmp_cmd_gas(cmd_gas_id, action ) values(:new.id,3);
   end loop;


 --------------------------
 -- Container.Content.Add
 --------------------------
 elsif :new.COMMAND_TYPE_ID=25 then
   -- проверяем товар
   if nvl(:new.good_desc_id,'-')='-' then
     raise_application_error(-20070,'<Good_desc_id> must be not null!');
   end if;
   select count(*) into cnt  from good_desc where id=:new.good_desc_id;
   if cnt=0 then
     raise_application_error(-20070,'<Good_desc_id> not found in database!');
   end if;
   select good_desc_id into gd_id_ from good_desc where id=:new.good_desc_id;

   -- проверяем контейнер
   if :new.CONTAINER_BARCODE is null then
     raise_application_error(-20070,'CONTAINER_BARCODE must be not Null!');
   end if;
   :new.container_barcode:=trim(:new.container_barcode);
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
   else
     select id into :new.container_id from container where barcode=:new.container_barcode;
   end if;
   service.log2file('  команда Container.Content.Add box='||:new.CONTAINER_BARCODE||'; cmd_type='||:new.command_type_id||'; qty='||:new.quantity||'; good_desc_id='||:new.good_desc_id);

   if is_party_c =1 then
     --  если нет пустой партии, добавляем
     if nvl(:new.gd_party_id,0)=0 then
       insert into gd_party (pname, gd_id)
       select null, gd.good_desc_id
       from good_desc gd
       where gd.id=:new.good_desc_id and not exists (select * from gd_party where pname is null and gd_id=gd.good_desc_id);
       select id into gdp_id__ from gd_party where pname is null and gd_id=gd_id_;
       :new.gd_party_id:=gdp_id__;
     else
       gdp_id__:=:new.gd_party_id;
     end if;
   else
     gdp_id__:=:new.gd_party_id;
   end if;

   -- делаем действия
   select count(*) into cnt from container_content
   where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=nvl(gdp_id__,0) ;
   if cnt=0 then
     -- нету такого в составе контейнера, добавляем insert
     insert into container_content (container_id, good_desc_id, quantity, gdp_id)
     values(:new.container_id, :new.good_desc_id, :new.quantity, gdp_id__);
   else
     -- есть такой, update
     -- а теперь состав контейнера
     update container_content set quantity=quantity+:new.quantity
     where container_id=:new.container_id and good_desc_id=:new.good_desc_id and nvl(gdp_id,0)=nvl(gdp_id__,0);
   end if;

   -- и из товаров убираем
   if sb_firm=1 then
     for frm in (select firm_id id from container where id=:new.container_id) loop
       if nvl(frm.id,0)=0 then
         raise_application_error(-20070,'Нельзя докладывать товар в контейнер, непривязанный к клиенту!');
       end if;
       begin
         insert into firm_gd (firm_id, gd_id, quantity, quantity_reserved )
         values(frm.id,:new.good_desc_id,:new.quantity,0);
       exception when others then
         update firm_gd set quantity=quantity+:new.quantity where gd_id=:new.good_desc_id and firm_id=frm.id;
       end;
     end loop;
   elsif is_party_c=1 then

     update gd_party
     set qty=qty+ :new.quantity
     where gd_id=gd_id_ and (pname is null and nvl(:new.gd_party_id,0)=0 or :new.gd_party_id=id);

   else
     update good_desc set quantity=quantity+:new.quantity where id=:new.good_desc_id;
   end if;
   :new.state:=5;
   :new.state_ind:=:new.state;

   for rr in (select name from repository where nvl(IS_STRONG_PRIHOD_CHECK,0)=1) loop
     -- триггер на автообновление статусов приходных накладных
     insert into tmp_cmd_gas(cmd_gas_id, action ) values(:new.id,1);
     obj_doc_expense.strong_pri_check1(:new.good_desc_id, :new.gd_party_id, :new.quantity, :new.pri_doc_number);
   end loop;
   :new.DATE_TIME_END:=sysdate;


 --------------------------
 -- Container.Content.Inventory
 --------------------------
 elsif :new.COMMAND_TYPE_ID=26 then
   -- проверка на не NULL
   if :new.CONTAINER_BARCODE is null then
     raise_application_error(-20070,'CONTAINER_BARCODE must be not Null!');
   end if;
   if :new.content  is null then
     raise_application_error(-20070,'content must be not Null!');
   end if;
   -- проверяем контейнер
   :new.container_barcode:=trim(:new.container_barcode);
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode <'||:new.container_barcode||'> doesn''t  exists!');
   else
     select id into :new.container_id from container where barcode=:new.container_barcode;
     container_id_:=:new.container_id;
   end if;
   service.log2file('  команда Container.Content.Inventory box='||:new.CONTAINER_BARCODE||'; cmd_type='||:new.command_type_id||'; qty='||:new.quantity||'; gd_id_s='||:new.content);

   -- разбор строки состава принимаемого контейнера
   obj_cmd_gas.parse_cg_cc(:new.id, :new.content, cmgd );
   -- удаляем то, что удалили прям строкой во время ревизии
   for del_cc in (select distinct cc.id, cc.good_desc_id, quantity , gdp_id
                  from container_content cc
                  where container_id=:new.container_id
                  and not exists (select * from command_gas_container_content cgcc
                                  where cgcc.command_gas_id=:new.id and nvl(cgcc.gdp_id,0)=nvl(cc.gdp_id,0) and cc.good_desc_id=cgcc.gd_id)) loop
      dbms_output.put_line('удаляем то, что удалили прям строкой gd_id='||del_cc.good_desc_id||' party='||del_cc.gdp_id);
      insert into command_gas_container_content (command_gas_id, gd_id, qty, notes, qty_delta, gdp_id)
      values (:new.id, del_cc.good_desc_id, 0, 'ав.сген.',-del_cc.quantity, del_cc.gdp_id);
      if sb_firm=1 then
        for frm in (select firm_id id from container where id=:new.container_id) loop
            update firm_gd set quantity=quantity-del_cc.quantity where gd_id=del_cc.good_desc_id and firm_id=frm.id;
        end loop;
      else
        if is_party_c=1 then -- по партиям
          update gd_party set qty=qty-del_cc.quantity where id=del_cc.gdp_id;
        else
          update good_desc set quantity=quantity-del_cc.quantity where id=del_cc.good_desc_id;
        end if;
      end if;
      update container_content cc set quantity=0 where cc.id=del_cc.id and nvl(cc.gdp_id,0)=nvl(del_cc.gdp_id,0);
   end loop;
   -- удаляем то, чего не хватает
   for del_cq in (select distinct cc.id, cc.good_desc_id, quantity, qty, cc.gdp_id
                  from container_content cc,  command_gas_container_content cgcc
                  where container_id=:new.container_id and cgcc.command_gas_id=:new.id
                        and nvl(cgcc.gdp_id,0)=nvl(cc.gdp_id,0)
                        and cc.good_desc_id=cgcc.gd_id and cgcc.qty<cc.quantity) loop
      dbms_output.put_line('удаляем то, чего не хватает '||del_cq.good_desc_id);
      update command_gas_container_content set qty_delta=-(del_cq.quantity-del_cq.qty)
      where command_gas_id=:new.id and gd_id=del_cq.good_desc_id and nvl(gdp_id,0)=nvl(del_cq.gdp_id,0);
      if sb_firm=1 then
        for frm in (select firm_id id from container where id=:new.container_id) loop
            update firm_gd set quantity=quantity-(del_cq.quantity-del_cq.qty) where gd_id=del_cq.good_desc_id and firm_id=frm.id;
        end loop;
      else
        if is_party_c=1 then -- по партиям
          update gd_party set qty=qty-(del_cq.quantity-del_cq.qty) where id=del_cq.gdp_id;
        else
          update good_desc set quantity=quantity-(del_cq.quantity-del_cq.qty) where id=del_cq.good_desc_id;
        end if;
      end if;
      update container_content cc set quantity=del_cq.qty where cc.id=del_cq.id;
   end loop;
   -- добавляем то, чего больше
   for add_cq in (select distinct cc.id, cc.good_desc_id, quantity, qty , cc.gdp_id
                  from container_content cc,  command_gas_container_content cgcc
                  where container_id=:new.container_id and cgcc.command_gas_id=:new.id
                        and nvl(cc.gdp_id,0)=nvl(cgcc.gdp_id,0)
                        and cc.good_desc_id=cgcc.gd_id and cgcc.qty>cc.quantity) loop
      dbms_output.put_line('добавляем то, чего больше '||add_cq.good_desc_id);
      if sb_firm=1 then
        for frm in (select firm_id id from container where id=:new.container_id) loop
            update firm_gd set quantity=quantity+(add_cq.qty-add_cq.quantity) where gd_id=add_cq.good_desc_id and firm_id=frm.id;
        end loop;
      else
        if is_party_c=1 then -- по партиям
          update gd_party set qty=qty+(add_cq.qty-add_cq.quantity) where id=add_cq.gdp_id;
        else
          update good_desc set quantity=quantity+(add_cq.qty-add_cq.quantity) where id=add_cq.good_desc_id;
        end if;
      end if;
      update container_content cc set quantity=add_cq.qty where cc.id=add_cq.id;
      update command_gas_container_content set qty_delta=(add_cq.qty-add_cq.quantity)
      where command_gas_id=:new.id and gd_id=add_cq.good_desc_id and nvl(gdp_id,0)=nvl(add_cq.gdp_id,0);
   end loop;
   -- прибавляем то, чего не было, но появилось строчками
   for add_cc in (select distinct gd_id, qty , gdp_id
                  from command_gas_container_content cgcc
                  where cgcc.command_gas_id=:new.id
                  and not exists (select * from container_content cc
                                  where container_id=:new.container_id
                                        and nvl(cc.gdp_id,0)=nvl(cgcc.gdp_id,0)
                                        and cc.good_desc_id=cgcc.gd_id)) loop
      if sb_firm=1 then
        for frm in (select firm_id id from container where id=:new.container_id) loop
          select count(*) into cnt from firm_gd where firm_id=frm.id and gd_id=add_cc.gd_id;
          if cnt>0 then
            update firm_gd set quantity=quantity+add_cc.qty where gd_id=add_cc.gd_id and firm_id=frm.id;
          else
            insert into firm_gd (firm_id, gd_id, quantity)
            values(frm.id, add_cc.gd_id,add_cc.qty);
          end if;
        end loop;
      else
        if is_party_c=1 then -- по партиям
          update gd_party set qty=qty+add_cc.qty where id=add_cc.gdp_id;
        else
          update good_desc set quantity=quantity+add_cc.qty where id=add_cc.gd_id;
        end if;
      end if;
      insert into container_content (container_id, good_desc_id, quantity, gdp_id)
      values(:new.container_id,add_cc.gd_id, add_cc.qty, add_cc.gdp_id);
      update command_gas_container_content set qty_delta=add_cc.qty
      where command_gas_id=:new.id and gd_id=add_cc.gd_id and nvl(gdp_id,0)=nvl(add_cc.gdp_id,0);
   end loop;

   -- заполненность контейнера прописываем
   if :new.container_fullness is not null then
     if not (:new.container_fullness between 0 and 1 ) then
       raise_application_error(-20070,'Container fullness must be between 0 and 1!');
     end if;
     update container set fullness=:new.container_fullness where id=container_id_;
   end if;
   :new.state:=5;
   :new.state_ind:=:new.state;

 --------------------------
 -- Container.Firm.Change
 --------------------------
 elsif :new.COMMAND_TYPE_ID=28 then
   select storage_by_firm into cnt from repository;
   if cnt=1 then
     if nvl(:new.firm_id,0)=0 then
       raise_application_error(-20070,'New firm_id must be not Null!');
     end if;
     if nvl(:new.old_firm_id,0)=0 then
       raise_application_error(-20070,'Old firm_id must be not Null!');
     end if;
   end if;
   if :new.container_barcode is null then
     raise_application_error(-20070,'Container barcode must be not Null!');
   end if;
   -- проверяем контейнер
   if :new.container_id is null then
     select count(*) into cnt from container where barcode=:new.container_barcode;
     if cnt=0 then
       raise_application_error(-20070,'Container with barcode='||:new.container_barcode||' is''nt in database');
     end if;
     select id into :new.container_id from container where barcode=:new.container_barcode;
   end if;
   insert into command_gas_container_content (command_gas_id, gd_id, qty)
   select :new.id, good_desc_id , quantity  from container_content where container_id=:new.container_id;
   :new.state:=5;
   :new.state_ind:=:new.state;

 --------------------------
 -- Container.Return
 --------------------------
 elsif :new.COMMAND_TYPE_ID=18 then
   -- raise_application_error(-20070,'Test!'); строка 951 т.е. +5
   if obj_ask.is_can_accept_cmd=0 then
     raise_application_error(-20071,service.ml_get_rus_eng_val('Ошибка! Нельзя давать команды АСК, находящемуся в режиме паузы!',
                'ERROR: Repository must be in work mode!'));
   end if;

   -- проверяем, а не по ID ли команда
   if nvl(:new.container_id,0)<>0 then
     select barcode into :new.CONTAINER_BARCODE from container where id=:new.container_id;
   end if;
   if nvl(:new.cell_id,0)<>0 then
     select sname, repository_part_id into  :new.cell_name, :new.rp_id
     from cell where id=:new.cell_id;
   end if;

   -- проверка на не NULL
   if :new.CONTAINER_BARCODE is null then
     raise_application_error(-20070,'CONTAINER_BARCODE must be not Null!');
   end if;
   -- проверка склада
   if :new.rp_id is null then
     select count(*) into cnt from repository_part where purpose_id in (2,3);
     if cnt=1 then
       select id into :new.rp_id from repository_part where purpose_id in (2,3);
     else
       for ccel in (select cell.repository_part_id from container con, cell where con.barcode=:new.container_barcode and con.cell_id=cell.id and hi_level_type in (14,15)) loop
         :new.rp_id:=ccel.repository_part_id;
       end loop;
       if :new.rp_id is null then
         raise_application_error(-20070,'<rp_id> must be not Null!');
       end if;
     end if;
   end if;
   -- проверка ячеек
   if :new.cell_name is null then
     select count(*) into cnt from cell where repository_part_id=:new.rp_id and hi_level_type in (15,14) and is_error<>1;
     if cnt=1 then
       select sname into :new.cell_name from cell where repository_part_id=:new.rp_id
       and hi_level_type in (15,14) and is_error<>1;
     else
       for ccel in (select sname from container con, cell where con.barcode=:new.container_barcode and con.cell_id=cell.id and hi_level_type in (14,15)) loop
         :new.cell_name:=ccel.sname; -- контейнер и так находится в ячейке возврата или универсальной
       end loop;
       if :new.cell_name is null then
         raise_application_error(-20070,'<cell_name> must be not Null!');
       end if;
     end if;
   end if;
   -- проверяем контейнер
   select count(*) into cnt from container where barcode=:new.container_barcode;
   if cnt=0 then
     raise_application_error(-20070,'Container with barcode='||:new.container_barcode||' is''nt in database');
   end if;
   select id into cnt_id from container where barcode=:new.container_barcode;
   :new.container_id:=cnt_id;
   select sum(quantity) into cnt from container_content where container_id =cnt_id;
   if cnt=0 and IAEC=0 then
     raise_application_error(-20070,'Container with barcode='||:new.container_barcode||' is empty!');
   end if;
   select count(*) into cnt from container cn, cell c
   where cn.id=cnt_id and location=1 and cn.cell_id=c.id and c.hi_level_type=1;
   if cnt>0 then
      raise_application_error(-20070,'Container is already in repository!');
   end if;

   -- проверяем, а нет ли команды приема товара по этой же ячейке недоделанной
   for cgl in (select * from command_gas t
               where command_type_id=11
                     and state in (0,1,3)
                     and container_id=:new.container_id
                     and date_time_create>=sysdate-3) loop
      raise_application_error(-20070,'Cell <'||:new.cell_name||'> was already locked by accept command '||cgl.id||'!');
   end loop;

   -- проверяем склад возврата
   select count(*) into cnt from repository_part where id=:new.rp_id and PURPOSE_ID in (2,3);
   if cnt=0 then
     raise_application_error(-20070,'<rp_id> point to bad repositiry subtype!');
   end if;

   -- проверяем ячейку возврата
   :new.cell_name:=trim(:new.cell_name);
   select count(*) into cnt from cell where repository_part_id=:new.rp_id and sname=:new.cell_name and is_error=0 and hi_level_type in (14,15,16);
   if cnt=0 then
     raise_application_error(-20070,'Cell '||:new.cell_name||' is error or another type!');
   end if;
   select id into cell_id_ from cell where repository_part_id=:new.rp_id and sname=:new.cell_name and is_error=0 and hi_level_type in (14,15,16);

   -- проверяем, а нету ли уже команды полученной по этой ячейке/контейнеру
   select count(*) into cnt from command_gas
   where state in (0,1,3)
         and :new.CONTAINER_BARCODE=CONTAINER_BARCODE
         and command_type_id=18;
   if cnt<>0 then
     raise_application_error(-20070,'Command was already given by barcode='||:new.container_barcode);
   end if;

   -- в случае строгой проверки проверяем, а свободна ли ячейка
   if icasc=1 then
     select count(*) into cnt from cell
     where id=cell_id_ and nvl(container_id,0)<>:new.container_id and is_full>0;
     if cnt>0 then
       raise_application_error(-20070,'The cell <'||:new.cell_name||'> in rp '||:new.rp_id||' is full!');
     end if;
   end if;

   if obj_rpart.has_free_cell_by_cnt(:new.container_id)=0 then
      raise_application_error (-20003, 'Repository is overload (has_free)!', TRUE);
   end if;

   -- проверяем, а не дадена ли уже команда на заьор из этой же ячейки
   for cmd_ret in (select * from command_gas where command_type_id=11 and rp_id=:new.rp_id and :new.cell_name=cell_name and state=0) loop
        raise_application_error(-20070,'Commad conflict found!');
   end loop;


   :new.state:=1;

   -- проверяем, а не находился ли контейнер в другой ячейке универсальной
   for ccel in (select * from cell where cell.container_id=:new.container_id and sname<>:new.cell_name and is_full<>0 and hi_level_type=15) loop
       service.log2file('  возврат - случай когда контейнер ['||:new.container_barcode||'] был в другой ячейке '||ccel.sname);
       update cell set is_full=is_full-1, container_id=0 where id=ccel.id;
   end loop;

   -- а нету ли контейнера уже в ячейке приема?
   select count(*) into cnt from container
   where barcode=:new.container_barcode and cell_id=cell_id_ and location=1;
   if cnt<>0 then
     -- есть уже контейнер в ячейке возврата, можно сразу давать команду
       service.log2file('  возврат - случай когда контейнер в ячейке возврата уже '||
                        :new.rp_id||' '||:new.container_id||' '||:new.command_type_id||' '|| :new.cell_name||' '||:new.rp_id||' '|| new_rp_id);
       -- gas.get_cell_name_for_accept(:new.rp_id, :new.container_id, :new.command_type_id, :new.cell_name, :new.rp_id, new_rp_id);
       cell_sname_:= obj_cmd_gas.get_cell_name_for_accept(:new.rp_id, :new.container_id, :new.command_type_id, :new.cell_name, :new.rp_id, new_rp_id);
       for cc in (select cc.id from container_collection cc , container_collection_content ccc
                  where cc.state=0 and cc.container_barcode =:new.container_barcode
                        and ccc.cc_id=cc.id and (quantity_real+quantity_deficit)<>quantity_need) loop
          raise_application_error(-20070,'Container collection with id='||cc.id||' is not finished yet!');
       end loop;
       service.log2file('  ячейка для хранения определена как ='||cell_sname_||' rp_id='||new_rp_id);
       if cell_sname_<>'-' then
         :new.cell_out_name:=cell_sname_;
         select letter into :new.zone_letter from zone where id=(select zone_id
                                                           from cell
                                                           where sname=cell_sname_
                                                           and repository_part_id=:new.rp_id);

         if service.get_rp_param_number('Particular_Return_Priority',0)=1 then
           pri_:=:new.priority;
         else
           pri_:=obj_rpart.get_cmd_max_priority(:new.rp_id);
         end if;
         obj_ask.Set_Command(:new.id,1,:new.rp_id, :new.cell_name,
                new_rp_id,cell_sname_,pri_, :new.container_id);
         :new.state:=0;
       else
         raise_application_error(-20070,'Repository is overload (get_cell_name_for_accept)!');
       end if;
   else
       select count(*) into cnt from command_gas_out_container where container_id=:new.container_id; -- а был ли вообще подвоз по контейнеру когда либо?
       if cnt<>0 then -- подвоз был, пошла проверка
         -- проверяем процесс отбора по контейнеру
         select count(*) into cnt from container_collection cc where state=0 and container_barcode =:new.container_barcode;
         if cnt=0 then
             raise_application_error(-20070,'There is not opening collection for container with barcode='||:new.container_barcode||' and container is''nt in return cell!');
         else -- есть коллекция
           select id into cc_id_ from container_collection cc where state=0 and container_barcode =:new.container_barcode;
           select count(*) into cnt from container_collection_content ccc
           where cc_id=cc_id_ and (quantity_real+quantity_deficit)<>quantity_need;
           if cnt<>0 then
             raise_application_error(-20070,'Container collection with id='||cc_id_||' is not finished yet!');
           end if;
         end if;
       end if;
   end if;
   -- вроде все ок, делаем присваивания
   update container_collection cc set state=1
   where state=0 and container_barcode =:new.container_barcode;

   :new.container_cell_name:=:new.cell_name;
   :new.container_rp_id:=:new.rp_id;
   :new.state_ind:=:new.state;

   if cmgd=0 then -- если только один товар в контейнеере
     select good_desc_id, quantity  into :new.good_desc_id, :new.quantity
     from container_content where container_id=:new.container_id;
   end if;

 end if;

END;
/
