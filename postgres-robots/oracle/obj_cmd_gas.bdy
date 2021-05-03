create or replace package body obj_cmd_gas is -- объект команд перемещения контейнеров от внешней ИС


-- взять трек ячейки источника для приема контейнера (может не совпадать для разных складов)
-- если склад приемник и источник совпадает, то тот же трек возвращает
-- если не совпадает, то возвращает трек трансферной свободной ячейки
function Get_Acc_Cell_Src_npp_RP(rp_src_npp_ number, rp_src_id_ number, rp_dest_id_ number) return number is
begin
  if rp_src_id_ = rp_dest_id_ then
    return rp_src_npp_;
  else -- не совпадают склад-источник и приемник
    for cc in (select * from cell where repository_part_id=rp_dest_id_ and hi_level_type=7 order by is_full) loop
      return cc.track_npp;
    end loop;
  end if;
  return -1000;
end;

-- добавить строку в журнал (лог)
procedure Log(s_ varchar2) is
begin
  dbms_output.put_line(s_);
  obj_ask.log(s_);
end;

-- возвращает название и подсклад ячейки для хранения контейнера
-- принимает: склад, контейнер, команду, ячейку-источник, склад команды
-- возвращает - название ячейки и подсклад
function get_cell_name_for_accept(rp_id_ in number, cnt_id_  in number,  cg_type_id_ number,
     cg_cell_sname_ varchar2, cg_rp_id_ number, new_rp_id_ out number) return varchar2 is --cmd_gas_id_ in number
  cnt_rang__ number;
  cnt_rec__ container%rowtype;
  celli_rec__ cell%rowtype;
  last_save_cell_npp__ number;
  slog_ varchar2(4000);
  can_transit_ number;
  src_npp_for_transfer_ varchar2(1000);
  recot_ number;
begin
  Log('get_cell_name_for_accept rp_id_='||rp_id_ ||' cnt_id_='|| cnt_id_  ||' cg_type_id_='||  cg_type_id_ ||
            ' cg_cell_sname_='|| cg_cell_sname_ ||' cg_rp_id_='|| cg_rp_id_);
  -- взяли ранг
  select nvl(max(gd.abc_rang),0) into cnt_rang__
  from good_desc gd, container_content cc
  where container_id=cnt_id_ and cc.good_desc_id=gd.id;
  -- взяли инфу по контейнеру
  select * into cnt_rec__ from container c where  c.id=cnt_id_;
  -- взяли инфу по ячейке приема
  select * into celli_rec__ from cell where sname=cg_cell_sname_ and repository_part_id=rp_id_;
  select is_transit_between_part into can_transit_ from repository;
  select reserve_empty_cell_on_track into recot_ from repository_part where id=rp_id_;
  last_save_cell_npp__:=0;
  for ll in (select cmd.* from command cmd, cell c
             where cmd.RP_DEST_ID=rp_id_ and c.id=CELL_DEST_ID and hi_level_type=1 and date_time_create>sysdate-1 and state=5
             order by cmd.date_time_end  desc , cmd.id desc) loop
    last_save_cell_npp__:=ll.npp_dest;
    Log('  last_save_cell_npp__='||last_save_cell_npp__);
    exit;
  end loop;

  -- ищем ячейку
  if recot_=1 then
    -- откуда отборы активные
    src_npp_for_transfer_:='';
    for cga in (select * from command_gas
                where rp_id=rp_id_ and command_type_id=14 and state in (0)
                      and obj_rpart.Get_Cell_Track_Npp(obj_rpart.Get_Cell_ID_By_Name(rp_id_,cell_name))=celli_rec__.track_npp) loop
      for cnt in (select track_npp  from container cn, cell cl
                  where cn.id=cga.container_id and cell_id=cl.id) loop
        src_npp_for_transfer_:=src_npp_for_transfer_||'['||cnt.track_npp||']';
      end loop;
    end loop;
    Log('src_npp_for_transfer_='||src_npp_for_transfer_);
    for ncl in (select cl.* from cell cl, repository_part rp
                where
                        is_full=0 and nvl(blocked_by_ci_id,0)=0
                        and rp.id=cl.repository_part_id
                        and max_full_size>(select count(*) from cell_cmd_lock where cell_id=cl.id)
                        and nvl(is_error,0)=0
                        and hi_level_type=1
                        and zone_id<>0
                        and cell_size<=cnt_rec__.type
                        and rp.id=rp_id_
                        and
                          (src_npp_for_transfer_ is null and obj_rpart.calc_track_free_cell(rp.id,track_npp)>1
                           or nvl(instr(src_npp_for_transfer_,'['||track_npp||']'),0)>0
                          )
                        order by
                                 abs(cell_size-cnt_rec__.type), -- наиболее подходящая ячейка размера
                                 abs (cnt_rang__-zone_id),
                                 trunc(obj_rpart.calc_min_distance(rp.repository_type,max_npp,
                                    Get_Acc_Cell_Src_npp_RP(celli_rec__.track_npp,celli_rec__.repository_part_id,rp.id),
                                               cl.track_npp)/5), -- неважна точность, важно примерное расстояние
                                 abs(cl.track_npp-last_save_cell_npp__) desc, -- важна разность чтоб два робота напрягать
                                 abs(ascii(substr(orientaition,1,1))-ascii(substr(sbros_prev_orient,1,1))) desc ) loop
              Log(' obj_cmd_gas.get_cell_name_for_accept - найдена ячейка для хранения '||ncl.sname||' зона товара '||cnt_rang__);
              return ncl.sname;
    end loop;
    for ncl in (select cl.* from cell cl, repository_part rp
                where
                        is_full=0 and nvl(blocked_by_ci_id,0)=0
                        and rp.id=cl.repository_part_id
                        and max_full_size>(select count(*) from cell_cmd_lock where cell_id=cl.id)
                        and nvl(is_error,0)=0
                        and hi_level_type=1
                        and zone_id<>0
                        and cell_size<=cnt_rec__.type
                        and rp.id=rp_id_
                        and obj_rpart.calc_track_free_cell(rp.id,track_npp)>1
                        order by
                                 abs(cell_size-cnt_rec__.type), -- наиболее подходящая ячейка размера
                                 abs (cnt_rang__-zone_id),
                                 trunc(obj_rpart.calc_min_distance(rp.repository_type,max_npp,
                                    Get_Acc_Cell_Src_npp_RP(celli_rec__.track_npp,celli_rec__.repository_part_id,rp.id),
                                               cl.track_npp)/5), -- неважна точность, важно примерное расстояние
                                 abs(cl.track_npp-last_save_cell_npp__) desc, -- важна разность чтоб два робота напрягать
                                 abs(ascii(substr(orientaition,1,1))-ascii(substr(sbros_prev_orient,1,1))) desc ) loop
              Log(' obj_cmd_gas.get_cell_name_for_accept 2 - найдена ячейка для хранения '||ncl.sname||' зона товара '||cnt_rang__);
              return ncl.sname;
    end loop;
  else -- не надо дыру держать в каждом треке
    for ncl in (select cl.* from cell cl, repository_part rp
                where
                        is_full=0 and nvl(blocked_by_ci_id,0)=0
                        and rp.id=cl.repository_part_id
                        --and obj_ask.is_cell_locked_by_cmd(cl.id)=0
                        and max_full_size>(select count(*) from cell_cmd_lock where cell_id=cl.id)
                        and nvl(is_error,0)=0
                        and hi_level_type=1
                        and zone_id<>0
                        and cell_size<=cnt_rec__.type
                        and (can_transit_=1 or rp.id=rp_id_)
                        order by
                                 abs (repository_part_id-rp_id_ ), -- ищем на ближайшем подскладе
                                 abs(cell_size-cnt_rec__.type), -- наиболее подходящая ячейка размера
                                 --instr(src_npp_for_transfer_,'['||track_npp||']') desc, -- при возврате-приходе сразу пытаемся забрать
                                 abs (cnt_rang__-zone_id),
                                 trunc(obj_rpart.calc_min_distance(rp.repository_type,max_npp,
                                    Get_Acc_Cell_Src_npp_RP(celli_rec__.track_npp,celli_rec__.repository_part_id,rp.id),
                                               cl.track_npp)/5), -- неважна точность, важно примерное расстояние
                                 abs(cl.track_npp-last_save_cell_npp__) desc, -- важна разность чтоб два робота напрягать
                                 abs(ascii(substr(orientaition,1,1))-ascii(substr(sbros_prev_orient,1,1))) desc ) loop
              if ncl.repository_part_id<>rp_id_
                 and obj_rpart.is_exists_cell_type(rp_id_,obj_ask.CELL_TYPE_TR_CELL)=0
                 and obj_rpart.is_exists_cell_type(rp_id_,obj_ask.CELL_TYPE_TR_CELL_OUTCOMING)=0 then
                   Log(' obj_cmd_gas.get_cell_name_for_accept - нет мест для хранения ');
                   exit;
              end if;
              new_rp_id_:=ncl.repository_part_id;
              Log(' obj_cmd_gas.get_cell_name_for_accept - найдена ячейка для хранения '||ncl.sname||' зона товара '||cnt_rang__);
              return ncl.sname;
    end loop;
  end if;
  Log('ERROR - не найдена ячейка для хранения ');
  return '-';

end;

-- сформировать команды по приходу/возврату
procedure Form_Cmds_By_Pri_Vozvr is
  rp_d_id__ number;
  new_rp_id__ number;
  cell_sname__ varchar2(100);
  sbf__ number;
  rpmode__ number;
  mcd__ number;
  is_party_c__ number;
  curpri__ number;
begin
  select current_mode, MO_CMD_GAS_DEPTH, storage_by_firm, is_party_calc
  into rpmode__, mcd__, sbf__, is_party_c__
  from repository;

  for cg in (select * from command_gas g where command_type_id in (11,18) and state in (1,0)
             and not exists (select * from command where command_gas_id=g.id)) loop
    obj_ask.log('  GAS: анализируем command_gas nnn id='||cg.id );
    -- смотрим ячейку приема - не освободилась ли
    for ccg in (select * from cell where repository_part_id=cg.rp_id
                and sname=cg.cell_name
                and ((is_full=0) or (is_full=1 and cell.container_id=cg.container_id))
                and obj_ask.is_cell_locked_by_cmd(cell.id)=0) loop
      -- ура - можно работать
      -- уточняем rp_d_id для пилюгино
      for pp in (select rp.id from repository_part rp where purpose_id  in (2,3) order by abs(cg.rp_id-rp.id)) loop
        obj_ask.log('  GAS уточнили : rp_d_id='||rp_d_id__ );
        rp_d_id__:=pp.id;
        exit;
      end loop;

      obj_ask.log('  GAS: ячейка приема/возврата свободна или там уже стоит то что нужно' );
      cell_sname__:=get_cell_name_for_accept(rp_d_id__, cg.container_id, cg.command_type_id, cg.cell_name,
                                             cg.rp_id, new_rp_id__);
      rp_d_id__:=new_rp_id__;
      obj_ask.log('  GAS: ячейка для хранения определена как ='||cell_sname__||' склад для хранения='||new_rp_id__ );
      if cell_sname__<>'-' then
        if ccg.is_full=0 then
          if nvl(ccg.container_id,0)=0 then
            update cell set container_id=cg.container_id where id=ccg.id;
          else
            update cell set container_id=0 where id=ccg.id;
            update cell set container_id=cg.container_id where id=ccg.id;
          end if;
        end if;
        update command_gas set
           cell_out_name=cell_sname__,
           zone_letter=(select letter from zone where id=(select zone_id
                                                          from cell
                                                          where sname=cell_sname__
                                                          and repository_part_id=rp_d_id__))
        where id=cg.id;

        if ccg.is_full=0 then
          update cell set is_full=is_full+1 where id=ccg.id;
        end if;


        case cg.command_type_id
        when 11 then
          if service.get_rp_param_number('Particular_Accept_Priority',0)=1 then
            curpri__:=cg.priority;
          else
            curpri__:=cmd_priority_container_accept;
          end if;
        else curpri__:=obj_ask.get_cur_max_cmd_priority;
        end case;

        obj_ask.Set_Command(cg.id,1,
               cg.rp_id, cg.cell_name,
               rp_d_id__,cell_sname__,
               curpri__ , cg.container_id);

        -- увеличиваем кол-во при приеме
        if cg.command_type_id=11 then
            for ccgd in (select cc.*, gd.good_desc_id gdid_
                         from container_content cc, good_desc gd
                         where cc.container_id=cg.container_id and cc.good_desc_id=gd.id
                        ) loop
              obj_ask.log('  GAS учет кол-ва при приеме '||ccgd.id );

              if sbf__=1 then -- учет товаров по фирме
                begin
                  INSERT into firm_gd (firm_id, gd_id, quantity)
                  values(cg.firm_id,ccgd.good_desc_id,ccgd.quantity);
                exception when others then
                  update firm_gd set quantity=quantity+
                     ccgd.quantity
                  where gd_id=ccgd.good_desc_id and firm_id=cg.firm_id;
                end;
              elsif nvl(is_party_c__,0)=1 then -- учет по партиям
                obj_ask.log('  GAS учет по партиям ccgd.gdid_='||ccgd.gdid_||' ccgd.gdp_id='||ccgd.gdp_id||' ccgd.quantity='||ccgd.quantity );
                update gd_party
                set qty=qty+ ccgd.quantity
                where gd_id=ccgd.gdid_ and (pname is null and nvl(ccgd.gdp_id,0)=0 or ccgd.gdp_id=id);


              else -- общий учет товаров
                update good_desc set quantity=quantity+
                   ccgd.quantity
                where id=ccgd.good_desc_id;
              end if;
            end loop;
        end if;
        insert into shelving_need_to_redraw (shelving_id)
        select shelving_id from cell
        where id=ccg.id and not exists (select * from shelving_need_to_redraw where shelving_id=cell.shelving_id);
      end if;
    end loop;
  end loop;
  --commit;
end;

-- зарезервировать товар по команде
procedure gd_resrve_on_cg_otbor(rp_ repository_part%rowtype) is
  gdid_ number;
  gd_party_id_ number;
  qnt number;
  rps_rec repository%rowtype;
begin
    select *  into rps_rec from repository;
    -- вначале резервируем товар - пытаемся
    for nr in (select * from command_gas where state=0
               and rp_id=rp_.id
               and command_type_id=12 and reserved=0) loop
      select good_desc_id into gdid_ from good_desc where id=nr.good_desc_id;
      obj_ask.log('Резервируем товар '||gdid_);
      if rps_rec.storage_by_firm=1 then
        select sum(quantity) into qnt from firm_gd where gd_id=nr.good_desc_id and firm_id=nr.firm_id;
        if qnt>0 then
          -- есть что резервировать
          if qnt>=nr.quantity then
            qnt:=nr.quantity;
          end if;
          update firm_gd
          set quantity_reserved=quantity_reserved+qnt, quantity=quantity-qnt
          where gd_id=nr.good_desc_id and firm_id=nr.firm_id;
        end if;
      elsif nvl(rps_rec.is_party_calc,0)=1 then -- учет по партиям
        if nvl(nr.gd_party_id,0)=0 then -- пустая партия
          select id into gd_party_id_ from gd_party where gd_id=gdid_ and pname is null;
        else
          gd_party_id_:=nr.gd_party_id;
        end if;
        update gd_party
        set qty=qty+nr.quantity
        where gd_id=gdid_ and (pname is null and nvl(nr.gd_party_id,0)=0 or nr.gd_party_id=id);

      else -- учет не по партиям, ни по фирмам
        select sum(quantity) into qnt from good_desc where id=nr.good_desc_id;
        if qnt>0 then
          -- есть что резервировать
          if qnt>=nr.quantity then
            qnt:=nr.quantity;
          end if;
          update good_desc
          set quantity_reserved=quantity_reserved+qnt, quantity=quantity-qnt
          where id=nr.good_desc_id;
        end if;
      end if;
      update command_gas set reserved=1, quantity_promis=qnt where id=nr.id;
    end loop;
end;

-- исправить статус команд, если нужно
procedure prav_cg_status(rp_id_ number) is
begin
      -- проверяем, есть ли команды, по которым вроде все подвезено/подвозится, а они не в 3-м статусе
      for cg in (select /*+RULE*/ * from command_gas where state_ind in (0,1)
                   and command_type_id=12
                   and rp_id=rp_id_
                   and (quantity-get_always_out_bcg(id,good_desc_id, gd_party_id ))<=0) loop
        -- исправляем бардак
        update command_gas set state=3 where id=cg.id;
        obj_ask.log('    prav_cg_status: исправили бардак - перевели в 3-й статус command_gas с id='||cg.id );
      end loop;

      -- проверяем, есть ли уже выполненные команды, но все еще находящиес в статусе 3
      for cg in (select cg.id, cg.quantity, sum(cgop.quantity_to_pick) from
                 command_gas_out_container cgo, command_gas cg, command_gas_out_container_plan cgop
                 where cgo.cmd_gas_id=cg.id and state_ind=3
                        and cg.rp_id=rp_id_ and cgop.cmd_gas_id=cgo.cmd_gas_id and cgop.container_id=cgo.container_id
                 group by cg.id, cg.quantity
                 having sum(cgop.quantity_to_pick)>=cg.quantity) loop
        update command_gas set state=5 where id=cg.id;
        obj_ask.log('    prav_cg_status: исправили бардак - перевели в 5-й статус command_gas с id='||cg.id );
      end loop;

end;

-- сформировать команды для буферной зоны
function gen_cmd_from_buffer(rp_ repository_part%rowtype) return number is
  cnt number;
  cmd_LAST_id number;
  new_cmd_id number;
begin
  if rp_.use_buffer_concept=0 then
    return 0;
  end if;
      -------------------------------------------
      -- есть ли товар в буферной зоне склада отбора
      ------------------------------------------
      select count(*) into cnt from cell c
      where zone_id=0 and repository_part_id=rp_.id and hi_level_type=1
            and is_full=1 and service.is_cell_cmd_locked(c.id)=0;
      if cnt>0 then
        obj_ask.log('    GAS: есть полных буферных ячеек ='||cnt );
        -- а есть ли ячейки сброса свободные?
        select count(*) into cnt
        from cell c
        where c.is_full<c.max_full_size
              and repository_part_id=rp_.id and hi_level_type=12
              and is_error=0
              and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1;
        obj_ask.log('    GAS: и ячейки сброса освободились='||cnt );
        if cnt>0 then
          -- берем минимальную дистанцию между яч сброса и буф зоной
          for md in (select sbr.id sbr_id, sbr.sname sbr_sname,
                            buf.id buf_id, buf.sname buf_sname
                     from cell sbr, cell buf
                     where sbr.is_full<sbr.max_full_size and sbr.repository_part_id=rp_.id and sbr.hi_level_type=12
                     and sbr.is_error=0
                     and service.is_cell_accept_enable(sbr.is_full,sbr.max_full_size,sbr.id)=1
                     and buf.zone_id=0 and buf.repository_part_id=rp_.id and buf.hi_level_type=1
                     and buf.is_error=0
                     and buf.is_full=1 and service.is_cell_cmd_locked(buf.id)=0
                     order by
                       obj_ask.calc_distance(rp_.repository_type, rp_.max_npp,sbr.track_npp, buf.track_npp),
                       service.empty_cell_capability(sbr.is_full ,sbr.max_full_size,sbr.id)
                    ) loop
            -- есть и ячейка откуда, и ячейка куда
            obj_ask.log('    GAS: есть и ячейка откуда, и ячейка куда' );
            select max(id) into cmd_LAST_id from command
            where command_type_id=1 and cell_dest_id=md.buf_id
                  and state=5 and is_intermediate=1;
            for cmdlast in (select * from command where id=cmd_LAST_id) loop
              -- добавляем команду
              insert into command (command_gas_id,command_type_id, rp_src_id, cell_src_sname,
                                   rp_dest_id, cell_dest_sname, priority, container_id)
              values(cmdlast.command_gas_id,1,rp_.id, md.buf_sname,
                     rp_.id,md.sbr_sname,1, cmdlast.container_id)
              returning id into new_cmd_id;
              update container set cell_goal_id=obj_rpart.get_cell_id_by_name(rp_.id,md.sbr_sname)
              where id=cmdlast.container_id;
            end loop;
            exit;
          end loop;
          return 1;
        end if;
      end if;
      return 0;
end;

-- сформировать план подвоза контейнеров по заказу товаров
procedure gen_cnt_out_gd(rp_ repository_part%rowtype) is
  qty_ number;
  qty_cg_need number;
  qty_cnt_rest number;
begin
  for rps in (select id from repository where CONTAINER_MULTI_GD=0) loop
    for cg in (select * from command_gas where state_ind in (0)
                   and COMMAND_TYPE_ID=12 and rp_id=rp_.id and reserved=1) loop
      -- есть ли коллекции открытые по товару
      for cics in (select c.id, ccnt.good_desc_id, c.barcode,c.cell_id, sum(ccc.quantity_need-ccc.quantity_real-ccc.quantity_deficit) res, ccnt.quantity
                       from container c, container_collection cc, container_collection_content ccc, container_content ccnt
                       where
                         c.id=cc.container_id
                         and ccnt.container_id=c.id
                         and state=0
                         and ccc.cc_id=cc.id
                         and nvl(c.cell_id,0)>0 -- стоит в ячейке отбора
                         and ccnt.good_desc_id=cg.good_desc_id
                         and not exists (select * from container_collection where cmd_gas_id=cg.id and state=0) -- нет уже открытой коллекции
                       group by c.id, ccnt.good_desc_id, c.barcode,c.cell_id, ccnt.quantity
                       )  loop
        obj_ask.log('        GAS: есть коллекции для доп по конт '||cics.id||' '|| cics.barcode);
        if cics.quantity>cics.res then -- есть хапнуть
           qty_cnt_rest:=cics.quantity-cics.res;
           qty_cg_need:=cg.quantity;
           if qty_cnt_rest>=qty_cg_need then
             qty_:=qty_cg_need;
           else
             qty_:=qty_cnt_rest;
           end if;
           insert into COMMAND_GAS_OUT_CONTAINER_PLAN
             (cmd_gas_id, container_id, quantity_all, quantity_to_pick)
           values (cg.id, cics.id, qty_cnt_rest, qty_);

           obj_ask.log('        GAS: insert COMMAND_GAS_OUT_CONTAINER '||cg.id||' '|| cics.id||' '|| qty_ );
           insert into COMMAND_GAS_OUT_CONTAINER
             (cmd_gas_id, container_id, container_barcode, good_desc_id, quantity,
              cell_name)
           values (cg.id, cics.id, cics.barcode, cg.good_desc_id, qty_,
              obj_ask.get_cell_name(cics.cell_id));
           update command_gas set state=1 where id=cg.id;
        end if;
      end loop;
    end loop;
  end loop;
end;

-- сформировать план подвоза контейнеров по заказу товаров, если в одном контейнере может быть множество разных артикулов
procedure gen_cnt_out_multi_gd(rp_ repository_part%rowtype) is
  qnt_izlish number;
  cnt number;
  sq number;
  qnt number;
begin
      ------------------------------------------
      -- для склада с мультихранением товара - нет ли возможности забрать
      -- с уже подвезенных контейнеров по другим товарам
      for rps in (select id from repository where CONTAINER_MULTI_GD=1) loop
        for cg in (select * from command_gas where state_ind in (0,1,3)
                   and COMMAND_TYPE_ID=12 and rp_id=rp_.id) loop
          --obj_ask.log('    GAS: по мультигуду пытаемся впихнуть для команды '||cg.id );
          for cics in (select distinct c.id, ccnt.good_desc_id, c.barcode,
                              cc.cell_name, ccnt.gdp_id gd_party_id,
                              c.cell_id
                       from container c, container_collection cc, container_collection_content ccc, container_content ccnt
                       where
                         c.id=cc.container_id
                         and ccnt.container_id=c.id
                         and state=0
                         and ccc.cc_id=cc.id
                         and ccnt.good_desc_id=cg.good_desc_id
                         and nvl(ccnt.gdp_id,0)=nvl(cg.gd_party_id,0)) loop
            -- если контейнер на рабочем столе или в ячейке закр. за компом команды
            if nvl(cics.cell_id,0)=0 or service.is_cell_on_comp(cics.cell_id,cg.comp_name)=1 then
              obj_ask.log('      GAS: есть контейнер '||cics.id||' и условие пройдено' );
              qnt_izlish:=obj_cmd_order.get_container_izlish(cics.id,cics.good_desc_id, cics.gd_party_id);
              if qnt_izlish>0 then -- есть что пхнуть
                obj_ask.log('        GAS: qnt_izlish='||qnt_izlish );

                -- запланировано
                select count(*) into cnt from COMMAND_GAS_OUT_CONTAINER_PLAN
                where cmd_gas_id=cg.id and container_id=cics.id;
                --obj_ask.log('        GAS: ищем COMMAND_GAS_OUT_CONTAINER_PLAN sqc='||sqc||' cd.id='||cg.id||' cn.id='||cics.id||' cnt='||cnt );
                if cnt=0 then
                  sq:=cg.quantity-get_cg_was_cnt_planned(cg.id);
                  if qnt_izlish>=sq then
                    qnt:=sq;
                  else
                    qnt:=qnt_izlish;
                  end if;
                  insert into COMMAND_GAS_OUT_CONTAINER_PLAN
                    (cmd_gas_id, container_id, quantity_all, quantity_to_pick)
                  values (cg.id, cics.id, qnt_izlish, qnt);
                  obj_ask.log('        GAS: insert COMMAND_GAS_OUT_CONTAINER_PLAN '||cg.id||' '|| cics.id||' '|| qnt_izlish||' '|| qnt );
                end if;

                -- уже подвезено для работы
                select count(*) into cnt from COMMAND_GAS_OUT_CONTAINER
                where cmd_gas_id=cg.id and container_id=cics.id;
                if cnt=0 then
                  insert into COMMAND_GAS_OUT_CONTAINER
                    (cmd_gas_id, container_id, container_barcode, good_desc_id, quantity,
                     cell_name, gd_party_id)
                  values (cg.id, cics.id, cics.barcode, cg.good_desc_id, qnt_izlish,
                     obj_ask.get_cell_name(cics.cell_id), cg.gd_party_id);
                  obj_ask.log('        GAS: insert COMMAND_GAS_OUT_CONTAINER '||cg.id||' '|| cics.id||' '|| qnt_izlish );
                end if;

              end if;
            end if;
          end loop;
        end loop;
      end loop; -- поиска донапихания по мультитоварности контейнера

end;

-- нужно ли выйти из цикла формирования команд?
function otbor_loop_need_exit(rp_ repository_part%rowtype) return boolean is
  cnt number;
  cmd_return_cnt number;
begin
  for rps in (select * from repository) loop
      -- считаем число возвратов незадействованных
      select count(*) into cmd_return_cnt from command cmd, command_gas cg
      where cmd.state=1 and cmd.command_gas_id=cg.id and cg.command_type_id=18;
      obj_ask.log('    GAS: команд возврата насчитано cnt='||cmd_return_cnt);

      -- есть куда еще команд напихать (из нужных)?
      select count(*) into cnt from command_rp crp, command c, command_gas cg
      where crp.state=1 and crp.rp_id=rp_.id
            and crp.command_id=c.id
            and c.command_gas_id=cg.id
            and cg.command_type_id=12;
      if cnt>=(rps.MO_CMD_GAS_DEPTH-cmd_return_cnt) then
         obj_ask.log('    GAS: сейчас акт. cnt_command_rp='||cnt||', а max_cd='||rps.MO_CMD_GAS_DEPTH );
         return true;
      end if;

      -- и есть команды для напихания?
      select count(*) into cnt from command_gas cg, command_gas_cell_in cgc, cell c
      where state_ind in (0,1) and command_type_id=12 and rp_id=rp_.id
             and cgc.command_gas_id=cg.id and cgc.cell_id =c.id
             and (/*NVL(is_buffer_work,0)=0 */ 0=0 and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1
                  or
                 /* nvl(is_buffer_work,0)=1*/ 0=1 and exists (select * from cell cc where repository_part_id=rp_.id
                                                 and zone_id=0 and hi_level_type=1 and is_error=0
                                                 and service.is_cell_accept_enable(cc.is_full,cc.max_full_size,cc.id)=1));
        --and (last_analized is null or cur_date-last_analized>service.get_sec(1));
      --obj_ask.log('    GAS: сейчас акт. cnt command_gas='||cnt||'  выходим если =0 is_buffer_work='||is_buffer_work );
      if cnt=0 then
         obj_ask.log('    cmd_GAS: есть команды для напихания');
         return true;
      end if;

      -- а нет ли застрятого в транзите
      for zt in (select cg.* from cell c , command_gas cg, command_gas_out_container_plan cgop, command_gas_cell_in cgci
                 where hi_level_type=7 and is_full=1
                       and repository_part_id=rp_.id and cgop.container_id=c.container_id and cgop.cmd_gas_id=cg.id and cg.state_ind in (0,1,3)
                       and cgci.command_gas_id=cg.id
                       and not exists (select * from cell_cmd_lock where cell_id=cgci.cell_id)) loop -- нет команд
         obj_ask.log('    GAS: есть застрявший товар в транзите' );
         return false;
      end loop;


      -- и есть ли товар для отбора на складе отбора
      select count(*) into cnt
      from command_gas cg, container_content cc, container cn, cell
      where state_ind in (0,1) and command_type_id=12
            and cg.good_desc_id=cc.good_desc_id
            and nvl(cg.gd_party_id,0)=nvl(cc.gdp_id,0)
            and (rps.storage_by_firm=0 or cg.firm_id=cn.firm_id)
            and cg.rp_id=rp_.id
            and cell.container_id=cn.id
            and (
                (cell.hi_level_type =1 and zone_id<>0 and not exists (select * from command where state in (0,1,3) and container_id=cn.id))
                or
                (cell.hi_level_type =7 and exists (select * from command cmd, command_rp crp
                                                   where crp.state in (0,1,3)
                                                         and cmd.id=crp.command_id
                                                         and cmd.container_id=cn.id
                                                         and substate is null))
                )
            and service.is_cell_over_locked(cell.id)=0
            and cn.id=cc.container_id
            and cc.quantity>0;
      if cnt=0 then
         obj_ask.log('    o_GAS: товар для отбора на складе отбора='||cnt );
         return true;
      end if;


      return false;
  end loop;
end;

-- получиьт режим работы с буфером
function get_buffer_work_mode(rp_ repository_part%rowtype) return number is
  is_buffer_work number;
  cnt_robot_free number;
  cnt number;
begin
  for rps in (select * from repository) loop
    select count(*) into cnt_robot_free from robot
    where repository_part_id=rp_.id and obj_robot.Is_Robot_Ready_For_Cmd(id)=1;
    obj_ask.log('  роботов свободных='||cnt_robot_free);

      -- и есть ли ячейки свободные для приемки контейнеров?
      select count(*) into cnt
      from cell c, command_gas_cell_in cgc, command_gas cg
      where cg.command_type_id=12 and cg.state_ind in (0,1)
            and cgc.command_gas_id=cg.id
            and c.id=cgc.cell_id
            and cg.rp_id=rp_.id
            and c.is_full<c.max_full_size
            and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1;
      obj_ask.log('    GAS: есть ли ячейки свободные для приема='||cnt );
      if cnt=0 then
        -- нет свободных ячеек для приема
        -- если нет и роботов свободных, то отлуп
        if cnt_robot_free=0 then
          obj_ask.log('    GAS: нет ячеек для приема, и роботов свободных нет' );
          return -1;
        end if;
        -- смотрим, а может есть в буферной зоне местцо
        select count(*) into cnt
        from cell c
        where hi_level_type=1 and zone_id=0
              and is_error=0
              and c.is_full<c.max_full_size
              and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1;
        if cnt=0 or rp_.use_buffer_concept=0 then
          -- точно ничего нет для работы - вылазим
          return -1;
        else -- может что-то есть
          -- а есть ли нужный товар в зонах иных нежели А
          select count(*) into cnt
          from command_gas cg, container_content cc, container cn, cell, good_desc gd
          where state_ind in (0,1) and command_type_id=12
                and cg.good_desc_id=cc.good_desc_id
                and nvl(cg.gd_party_id,0)=nvl(cc.gdp_id,0)
                and (rps.storage_by_firm=0 or cg.firm_id=cn.firm_id)
                and cg.good_desc_id=gd.id
                and gd.abc_rang >obj_rpart.get_real_min_abc_zone(rp_.id) -- иная нежели Зона А, но не буфер
                and cell.container_id=cn.id
                and (
                    (cell.hi_level_type =1 and zone_id<>0 and not exists (select * from command where state in (0,1,3) and container_id=cn.id))
                    or
                    (cell.hi_level_type =7 and exists (select * from command cmd, command_rp crp
                                                       where crp.state in (0,1,3)
                                                             and cmd.id=crp.command_id
                                                             and cmd.container_id=cn.id
                                                             and substate is null))
                    )
                and cn.id=cc.container_id
                and service.is_cell_over_locked(cell.id)=0
                and cc.quantity>0;
          if cnt>0 then
            obj_ask.log('    GAS: НО есть место в буфере плюс товар заказной в ЗОНЕ >А' );
            is_buffer_work:=1; -- буфер иб ту ю мэмэ
          else
            return -1;
          end if;
        end if;

      else
        is_buffer_work:=0; -- есть ячейки реальные для сброса, никакого буфера
      end if;
      return is_buffer_work;
  end loop;
end;

-- получить максимальный приоритет команд по огурцу
function get_max_priority(rp_ repository_part%rowtype, cur_date date, is_buffer_work number) return number is
  pr number;
begin
      -- ищем макс. приоритет в котором вертеться
      select /*+RULE*/ max(priority) into pr from command_gas cg, good_desc gd
        where state_ind in (0,1) and command_type_id=12 and cg.good_desc_id=gd.id
              and (is_buffer_work=0 or gd.abc_rang >obj_rpart.get_real_min_abc_zone(rp_.id)) -- или не буфер, или иная зона нежели А
              and (last_analized is null or cur_date-last_analized>service.get_sec(10));
        obj_ask.log('    GAS: max(priority)='||pr );
      return pr;
end;

-- получить приоритетную стороны команды для огурца (чтоб не клинило механику робота нужно чередовать стороны)
function get_cmd_side(rp_ repository_part%rowtype) return number is
  cmd_0_side number;
  cmd_1_side number;
  cmd_side number;
  cnt number;
begin
      select count(*) into cmd_0_side
      from cell c1, cell c2, command cmd
      where cmd.rp_src_id=cmd.rp_dest_id and cmd.rp_dest_id=rp_.id and
            cell_src_id=c1.id and cell_dest_id=c2.id and c1.side=c2.side
            and state in (0,1,3) and command_type_id=1
            and c1.side=0;
      select count(*) into cmd_1_side
      from cell c1, cell c2, command cmd
      where cmd.rp_src_id=cmd.rp_dest_id and cmd.rp_dest_id=rp_.id and
            cell_src_id=c1.id and cell_dest_id=c2.id and c1.side=c2.side
            and state in (0,1,3) and command_type_id=1
            and c1.side=1;
      if cmd_0_side>cmd_1_side then
        cmd_side:=1;
      elsif cmd_0_side<cmd_1_side then
        cmd_side:=0;
      else
        cmd_side:=-1; -- по фиг какая
      end if;
      obj_ask.log('    GAS: cmd_side='||cmd_side );

      -- уточняем сторону
      if cmd_side<>-1 then
        -- если есть предпочтение по стороне, то смотрим, а есть ли там свободные приемные ячейки
        select nvl(sum(service.empty_cell_capability(c.is_full,c.max_full_size,c.id)),0)
             into cnt
             from cell c, command_gas_cell_in cgc, command_gas cg
             where cg.command_type_id=12 and cg.state_ind in (0,1)
                   and cgc.command_gas_id=cg.id
                   and c.id=cgc.cell_id
                   and c.side=cmd_side
                   and cg.rp_id=rp_.id
                   and c.is_full<c.max_full_size
                   and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1;
        if cnt=0 then -- по порядку сия сторона, а сувать некуда
          obj_ask.log('    GAS: в выбранной стороне нет свободного места для сброса' );
          select nvl(sum(service.empty_cell_capability(c.is_full,c.max_full_size,c.id)),0)
               into cnt
               from cell c, command_gas_cell_in cgc, command_gas cg
               where cg.command_type_id=12 and cg.state_ind in (0,1)
                     and cgc.command_gas_id=cg.id
                     and c.id=cgc.cell_id
                     and c.side=decode(cmd_side,1,0,1)
                     and cg.rp_id=rp_.id
                     and c.is_full<c.max_full_size
                     and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1;
          if cnt<>0 then -- можем присунуть сюда
            select decode(cmd_side,1,0,1)  into cmd_side from dual;
            obj_ask.log('  GAS: меняем cmd_side на '||cmd_side );
          end if;
        end if;
      end if;

      return cmd_side;
end;

-- получить последнюю сторону команды для конкретной зоны
function get_last_side_zone(rp_id_ in number, side_ number) return number is
  res number;
begin
  select zone_id into res from last_side_zone where side=side_ and rp_id=rp_id_;
  return res;
  exception when others then
    return 1;
end;


-- установить последнюю сторону команды для конкретной зоны
procedure set_next_last_side_zone(rp_id_ in number, side_ number) is
  res number;
  tmp number;
  nres number;
  cnt number;
begin
  res:=get_last_side_zone(rp_id_ , side_);
  select max(id) into tmp from zone;
  if res=tmp then
    select min (id) into nres from zone where id<>0;
  else
    select min (id) into nres from zone where id>res;
  end if;
  select count(*) into cnt from last_side_zone
  where side=side_ and rp_id=rp_id_;
  if cnt=0 then -- нету - добавляем
    insert into last_side_zone(rp_id, side, zone_id)
    values(rp_id_, side_, nres);
  else -- обновляем
    update last_side_zone
    set zone_id=nres
    where rp_id=rp_id_ and side=side_;
  end if;
end;

-- есть ли незанятые командами ячейки для сброса
function is_cg_otbor_cell_out_unlock(cg_id_ number) return number is
begin
  for cg in (select * from command_gas_cell_in cgci where command_gas_id=cg_id_ and not exists (select * from cell_cmd_lock where cell_id=cgci.cell_id))
  loop
    return 1;
  end loop;
  return 0;
end;

-- залоггировать факт назначения команды
procedure log_cg_set_cmd(cg_id_ number) is
  cnt_ number;
begin
  for cc in (select cell.sname, cell.id
                 from cell, command_gas_cell_in cmdc
                 where cmdc.command_gas_id=cg_id_
                       and  cmdc.cell_id=cell.id
                       and cell.is_full<cell.max_full_size
                 ) loop
          obj_ask.log('    GAS: log_cg_set_cmd cell.is_full<cell.max_full_size:'||cc.sname );
  end loop;
  for cc in (select cell.sname, cell.id
                 from cell, command_gas_cell_in cmdc
                 where cmdc.command_gas_id=cg_id_
                       and  cmdc.cell_id=cell.id
                       and cell.repository_part_id in (select id from repository_part where purpose_id in (2,3)) --rp.id  можно убрать
                 ) loop
          obj_ask.log('    GAS: log_cg_set_cmd cell.repository_part_id in '||cc.sname );
  end loop;
  for cc in (select cell.sname, cell.id
                 from cell, command_gas_cell_in cmdc
                 where cmdc.command_gas_id=cg_id_
                       and  cmdc.cell_id=cell.id
                       and service.is_cell_accept_enable(is_full,max_full_size,cell.id)=1
                 ) loop
          obj_ask.log('    GAS: log_cg_set_cmd is_cell_accept_enable '||cc.sname );
  end loop;
  for cc in (select cell.sname, cell.id
                 from cell, command_gas_cell_in cmdc
                 where cmdc.command_gas_id=cg_id_
                       and  cmdc.cell_id=cell.id
                       and obj_ask.Is_Cell_Locked_By_Cmd(cell.id)=0 -- не стоит пихать туда, где уже есть команда
                 ) loop
          obj_ask.log('    GAS: log_cg_set_cmd Is_Cell_Locked_By_Cmd '||cc.sname );
  end loop;
  for cc in (select cell.sname, cell.id
                 from cell, command_gas_cell_in cmdc
                 where cmdc.command_gas_id=cg_id_
                       and  cmdc.cell_id=cell.id
                       and not exists (select * from cell_cmd_lock where cell_id=cell.id) -- точно нет команд
                 ) loop
          obj_ask.log('    GAS: log_cg_set_cmd not exists cmd_lock - '||cc.sname );
  end loop;
  exception when others then
          obj_ask.log('    GAS: log_cg_set_cmd not - ошибка создания лога ');
end;


-- обработка команд в цикле
procedure handle_cgas_on_loop(rp_ repository_part%rowtype, is_buffer_work number, pr number, cmd_side number, cur_date date) is
  sq number;
  sqc number;
  is_found_cnt boolean;
  cnt number;
  cmd_id number;
  cell_d_id number;
  cmd_state number;
  new_cmd_id number;
begin
  for rps in (select * from repository) loop
      -- берем в цикле одну command_gas с которой работаем ^^^
      obj_ask.log('      GAS: начинаем цикл по командам отбора rp.id='||rp_.id||' is_buffer_work='||is_buffer_work||' cmd_side='||cmd_side||' pr='||pr||' cur_date='||to_char(cur_date, 'dd.mm.yy hh24:mi') );
      for cg in (select cgl.id, cgl.quantity, cgl.good_desc_id, cgl.priority, cgl.firm_id, gd_party_id,
                 presence_in_side(cgl.id,cmd_side) pp
                 from command_gas cgl, good_desc gd
                 where cgl.state_ind in (0,1) and cgl.command_type_id=12
                  and pr=priority
                  and is_cg_otbor_cell_out_unlock(cgl.id)=1 -- есть ли ячейки незаблоченые для сброса по команде?
                  and (cgl.last_analized is null or cur_date-cgl.last_analized>service.get_sec(10))
                  and cgl.good_desc_id=gd.id
                  and cgl.rp_id=rp_.id
                  and get_cg_was_cnt_planned(cgl.id)<nvl(cgl.quantity,0) -- чтоб уже распланированные не тянуть
                  and (is_buffer_work=0 or gd.abc_rang >obj_rpart.get_real_min_abc_zone(rp_.id)) -- или не буфер, или иная зона нежели А
                  order by
                    cgl.priority,
                    gd.abc_rang-get_last_side_zone(rp_.id,cmd_side), -- вначале привозим из зоны А
                    presence_in_side_accurance(rp_.id, rp_.max_npp, -- =0 если сторона что надо
                       cgl.id,cmd_side,rps.current_mode,
                       cgl.quantity-get_always_out_bcg(cgl.id, cgl.good_desc_id, cgl.gd_party_id),
                       gd.id),
                    cgl.id -- чтоб старые привозило
                    --presence_in_side(cgl.id,cmd_side),
                     ) loop
        obj_ask.log('        GAS: нашли необходимую command_gas='||cg.id );
        set_next_last_side_zone(rp_.id,cmd_side);
        --sq:=cg.quantity-gas.get_always_out_bcg(cg.id, cg.good_desc_id, cg.gd_party_id); тут ошибка - не то вызывалось
        sq:=cg.quantity-get_cg_was_cnt_planned(cg.id);
        obj_ask.log('        GAS: посчитали сколько отсалось подвезти = '||sq );
        if sq<=0 then
          --update command_gas set state=3 where id=cg.id; -- усе уже есть, странно что сюда дошли
          obj_ask.log('        ERROR - GAS: sq<=0 '||sq );
        else

          -- есть еще неназначенный товар по этой команде
          obj_ask.log('        GAS: ищем т.к. sq= '||sq||' >0' );

          -- берем одну ячейку - источник, откуда контейнер ### тута надо вставить ###
          is_found_cnt:=false;
          for cn in (select c.sname, cn.id, c.track_npp, c.hi_level_type, c.repository_part_id,
                            c.id cell_id, ccont.quantity
                     from cell c, container cn , container_content ccont
                     where cn.cell_id=c.id and ccont.good_desc_id=cg.good_desc_id
                     and nvl(ccont.gdp_id,0)=nvl(cg.gd_party_id,0)
                     and (rps.storage_by_firm=0 or cg.firm_id=cn.firm_id)
                     and c.repository_part_id in (select id from repository_part where purpose_id in (2,3)) --rp.id -- ищем товар где угодно
                     and ccont.container_id=cn.id
                     and (
                        (hi_level_type =1 and c.zone_id<>0) or
                        (hi_level_type =7 and exists(select * from command_rp where command_type_id=3 and state in (1,3) and c.id =cell_src_id and substate is null))
                        )
                     and service.is_cell_over_locked(c.id)=0
                     and ccont.quantity>0
                     order by abs(c.repository_part_id-rp_.id), -- берем из текущего склада, но если не находим, то хоть откуда нибудь
                              obj_cmd_gas.get_quantity_accordance(sq,rps.current_mode,ccont.quantity),
                              decode(cmd_side,-1,0,abs(c.side-cmd_side)),
                              obj_rpart.calc_robot_nearest(rp_.id, rp_.max_npp, c.track_npp)) loop

              is_found_cnt:=true;
              obj_ask.log('        GAS: нашли ячейку-откуда брать='||cn.sname||' со склада '||cn.repository_part_id );

              -- делаем план по контейнерам
              if sq<=cn.quantity then -- контейнер найденный полностью покрывает нужду
                sqc:=sq;
              else
                sqc:=cn.quantity;
              end if;
              select count(*) into cnt from COMMAND_GAS_OUT_CONTAINER_PLAN
              where cmd_gas_id=cg.id and container_id=cn.id;
              obj_ask.log('        GAS: ищем COMMAND_GAS_OUT_CONTAINER_PLAN sqc='||sqc||' cd.id='||cg.id||' cn.id='||cn.id||' cnt='||cnt );
              if cnt=0 then
                insert into COMMAND_GAS_OUT_CONTAINER_PLAN
                  (cmd_gas_id, container_id, quantity_all, quantity_to_pick)
                values (cg.id, cn.id, cn.quantity, sqc);
                obj_ask.log('        GAS: insert COMMAND_GAS_OUT_CONTAINER_PLAN '||cg.id||' '|| cn.id||' '|| cn.quantity||' '|| sqc );

                if cn.hi_level_type=7 then -- если ячейка-источник = транзитной
                  obj_ask.log('    GAS: ячейка-источник транзитная' );
                  -- надо завершить команду приема товара успешно досрочно
                  select id, cell_dest_id, state
                  into cmd_id , cell_d_id, cmd_state
                  from command
                  where state in (0,1,3) and command_type_id=1
                  and container_id=(select container_id from cell where id=cn.cell_id);
                  obj_ask.log('    GAS: команда для досрочного завершения='||cmd_id);
                  service.cell_unlock_from_cmd(cell_d_id,cmd_id);
                  -- удаляем crp
                  delete from command_rp
                  where command_id=cmd_id
                        and rp_id=rp_.id
                        and state in (1,3)
                        and substate is null
                        and rp_id=rp_.id
                        and cell_src_id =cn.cell_id;
                  update robot set command_rp_id=0 where not exists (select * from command_rp where id=command_rp_id);
                  update command set state=5, cell_dest_sname =cn.sname where id=cmd_id;
                  update command_gas set state=5, container_cell_name=cn.sname , container_rp_id=rp_.id
                  where id=(select command_gas_id from command where id=cmd_id) and command_type_id in (11,18);
                end if;

                -- узнали ячейку - источник, теперь приемник ищем
                if is_buffer_work=0 then -- прямо в ячейку сброса
                  obj_ask.log('    GAS: is_buffer_work=0' );
                  log_cg_set_cmd(cg.id);
                  for cc in (select cell.sname, cell.id
                             from cell, command_gas_cell_in cmdc
                             where cmdc.command_gas_id=cg.id
                                   and  cmdc.cell_id=cell.id
                                   and cell.is_full<cell.max_full_size
                                   and cell.repository_part_id in (select id from repository_part where purpose_id in (2,3)) --rp.id  можно убрать
                                   and service.is_cell_accept_enable(is_full,max_full_size,cell.id)=1
                                   and obj_ask.Is_Cell_Locked_By_Cmd(cell.id)=0 -- не стоит пихать туда, где уже есть команда
                                   and not exists (select * from cell_cmd_lock where cell_id=cell.id) -- точно нет команд
                                   -- идем другим путем
                             order by obj_ask.calc_distance(rp_.repository_type, rp_.max_npp, cell.track_npp, cn.track_npp)
                             ) loop
                      obj_ask.log('    GAS: нашли ячейку-куда ложить='||cc.sname );
                      -- добавляем команду
                      insert into command (command_gas_id,command_type_id, rp_src_id, cell_src_sname,
                                           rp_dest_id, cell_dest_sname, priority, container_id)
                      values(cg.id,1,cn.repository_part_id, cn.sname,
                             rp_.id,cc.sname,cg.priority , cn.id)
                      returning id into new_cmd_id;
                      update container set cell_goal_id=obj_rpart.get_cell_id_by_name(rp_.id,cc.sname)
                      where id=cn.id;
                      exit;
                  end loop;
                  exit;

                else -- в промежуточные ячейки везем
                  obj_ask.log('    GAS: поиск промежут rp.id='||rp_.id||' ' );
                  for cc in (select cell.sname
                             from cell
                             where zone_id=0
                                   and hi_level_type=1
                                   and is_error=0
                                   and cell.is_full<cell.max_full_size
                                   and cell.repository_part_id=rp_.id
                                   and service.is_cell_accept_enable(is_full,max_full_size,cell.id)=1
                                   -- идем другим путем
                             order by obj_ask.calc_distance(rp_.repository_type, rp_.max_npp, cell.track_npp, cn.track_npp)
                             ) loop
                    obj_ask.log('    GAS: нашли промежуточную ячейку в буфере ячейку-куда ложить='||cc.sname );
                    -- добавляем команду
                    insert into command (command_gas_id,command_type_id, rp_src_id, cell_src_sname,
                                         rp_dest_id, cell_dest_sname, priority, container_id, IS_INTERMEDIATE)
                    values(cg.id,1,cn.repository_part_id, cn.sname,
                           rp_.id,cc.sname,cg.priority , cn.id, 1)
                    returning id into new_cmd_id;
                    update container set cell_goal_id=obj_rpart.get_cell_id_by_name(rp_.id,cc.sname)
                    where id=cn.id;
                    exit;
                  end loop;
                  exit;
                end if;
              else
                    obj_ask.log('    GAS: ошибка CGOCP уник сработал бы' );
                    update command_gas set last_analized=cur_date where id=cg.id;
                    --return;
              end if;
          end loop;
          if not is_found_cnt then
            obj_ask.log('    GAS: нехватка товара' );
            update command_gas set last_analized=cur_date where id=cg.id;
          end if;
        end if;
        exit;
      end loop;
  end loop;
end;

-- восстановление потерянных из-за сбоя команд
procedure recovery_lost_cmd(rp_ repository_part%rowtype) is
  new_cmd_id number;
begin
      for cgw in (select /*+RULE*/ cg.id, cg.state, cg.priority, cn.cell_id , cs.repository_part_id rp_cs_id, cs.sname cs_name, cn.id cont_id
                  from command_gas cg, command_gas_out_container_plan cgo, cell c,
                     command_gas_cell_in cgc, container cn, cell cs
                  where
                    state_ind in (0,1) and cg.id=cmd_gas_id and not exists (select * from command cmd where command_gas_id=cg.id and cmd.container_id=cgo.container_id)
                    and cg.rp_id=rp_.id
                    and cgc.command_gas_id =cg.id
                    and cgo.container_id=cn.id
                    and cn.cell_id=cs.id
                    and cs.hi_level_type in (1,7) -- только из ячеек хранения или переозначенную транзитную
                    and c.id=cgc.cell_id
                    and not exists (select * from cell_cmd_lock where cell_id=c.id) -- точно нет команд
                    and service.is_cell_accept_enable(c.is_full,c.max_full_size,c.id)=1
                  order by cg.id) loop
          obj_ask.log('    GAS: нашли cogp ошибочную команду ='||cgw.id ||' из ячейки '||cgw.cs_name);
          if is_cg_otbor_cell_out_unlock(cgw.id)=1 then
            obj_ask.log('    GAS: is_cg_otbor_cell_out_unlock=1');
            if cgw.state=0 then
              update command_gas set state=1 where id=cgw.id;
            end if;
            for cc in (select cell.sname, cell.is_full, cell.max_full_size, cell.id
                       from cell, command_gas_cell_in cmdc
                       where cmdc.command_gas_id=cgw.id
                             and  cmdc.cell_id=cell.id
                             and cell.is_full<cell.max_full_size
                             and not exists (select * from cell_cmd_lock where cell_id=cell.id) -- точно нет команд
                             and cell.repository_part_id in (select id from repository_part where purpose_id in (2,3)) --rp.id  можно убрать
                             and service.is_cell_accept_enable(is_full,max_full_size,cell.id)=1
                       ) loop
              if service.is_cell_accept_enable(cc.is_full,cc.max_full_size,cc.id)=1 then
                obj_ask.log('    GAS: cogp нашли ячейку-куда ложить='||cc.sname );
                -- добавляем команду
                insert into command (command_gas_id,command_type_id, rp_src_id, cell_src_sname,
                                     rp_dest_id, cell_dest_sname, priority, container_id)
                values(cgw.id,1,cgw.rp_cs_id, cgw.cs_name,
                       rp_.id,cc.sname,cgw.priority , cgw.cont_id)
                returning id into new_cmd_id;
                update container set cell_goal_id=obj_rpart.get_cell_id_by_name(rp_.id,cc.sname)
                where id=cgw.cont_id;
              end if;
              exit;
            end loop;
          end if;
          exit; -- по одной команде берем в одну ячейку
      end loop;
end;

-- сформировать команды по отбору товаров
procedure Form_Cmds_By_Otbor is
  cnt number;
  rps_rec repository%rowtype;
  rp_rec repository_part%rowtype;
  cur_date date;
  max_loop_cnt number;
  loop_cnt number;
  is_buffer_work number; -- в буфер ли выгружаем(=1), или в ячейки сброса(=0)?
  pr number;
  cmd_side number;

begin

  cur_date:=sysdate();
  select *  into rps_rec from repository;

  for rp in (select * from repository_part where purpose_id in (2,3)) loop -- id, max_npp, repository_type
    obj_ask.log('Form_Cmds_By_Otbor: вошли в цикле в подсклад='||rp.id);
    gd_resrve_on_cg_otbor(rp);
    --up_prior_buf_if_ness(rp.id); -- смотрим - не надо ли что забрать срочно с буферного огурца


    -- пошел цикл главный
    max_loop_cnt:=4;
    loop_cnt:=0;
    obj_ask.log('  Form_Cmds_GAS_By_Otbor: начинаем цикл главный');
    loop
      loop_cnt:=loop_cnt+1;
      obj_ask.log('    Form_Cmds_gas_By_Otbor: цикл главный такт ***' );
      prav_cg_status(rp.id);

      cnt:=gen_cmd_from_buffer(rp);
      obj_ask.log('    gen_cmd_from_buffer='||cnt );
      exit when cnt=1;

      gen_cnt_out_multi_gd(rp);

      gen_cnt_out_gd(rp); -- можно ли хапануть с уже подвезенных контейнеров


      exit when otbor_loop_need_exit(rp);

      is_buffer_work:=get_buffer_work_mode(rp);
      obj_ask.log('    is_buffer_work='||is_buffer_work );
      exit when is_buffer_work<0;

      pr:=get_max_priority(rp, cur_date , is_buffer_work );
      obj_ask.log('    get_max_priority='||pr);
      exit when pr is null;

      -- проверим вариант, когда ошибочно план поставился, а реальная команда не далася
      recovery_lost_cmd(rp);

      -- определяем приоритетную сторону команды
      cmd_side:=get_cmd_side(rp);
      handle_cgas_on_loop(rp, is_buffer_work, pr, cmd_side , cur_date );

      exit when loop_cnt>max_loop_cnt;
    end loop; -- главного цикла
    obj_ask.log('  GAS: вышли из цикла главного');

  end loop;
end;

-- основная процедура - формирование команд
procedure Form_Commands is
  msg__ varchar2(500);
begin

  for rep in (select * from repository ) loop
    commit;  -- если пул остался незакоммиченным, корммитим

    begin
      Form_Cmds_By_Pri_Vozvr;
      commit;
    exception when others then
      msg__:='ERROR - ошибка из cmd_gas.Form_Commands-Form_Cmds_By_Pri_Vozvr: '||SQLERRM;
      rollback;
      obj_ask.global_error_log(obj_ask.error_type_ASK,null,null,msg__);
      obj_ask.Log(msg__);
    end;

    if rep.ABSTRACT_LEVEL>=3 then
      begin
        Form_Cmds_By_Otbor;
        commit;
      exception when others then
        msg__:='ERROR - ошибка из cmd_gas.Form_Commands-Form_Cmds_By_Otbor: '||SQLERRM;
        rollback;
        obj_ask.global_error_log(obj_ask.error_type_ASK,null,null,msg__);
        obj_ask.Log(msg__);
      end;
    end if;
  end loop;

end;

-- такт общего крэш-теста
procedure crash_test_cmd_Gas_tact(rp_id_ number) is
  lstate number;
  cnt__ number;
begin
  select count(*) into cnt__ from command_gas where rp_id=rp_id_ and  command_type_id=18 and state not in (2,5);
  obj_rpart.Log(rp_id_,'crash_test_cmd_Gas_tact cnt__='||cnt__);
  if cnt__<=3 then
    -- вначале вывозим все полные ячейки
    for cfull in (select cl.*, b.barcode bc from cell cl, container b
                  where hi_level_type in (15) and is_full=1 and container_id=b.id
                        and not exists (select * from cell_cmd_lock where cell_id=cl.id)
                        and repository_part_id=rp_id_ order by DBMS_RANDOM.random) loop
      obj_rpart.Log(rp_id_,'  c15name='||cfull.sname);
      -- ищем последнюю команду на возврат
      lstate:=5;
      for cmd in (select * from command_gas
                  where command_type_id=18 and cell_name=cfull.sname and rp_id=cfull.repository_part_id
                  order by id desc) loop
        lstate:=cmd.state;
        exit;
      end loop;
      if lstate=5 then --последняя команда выполнилась, даем новую
        obj_rpart.Log(rp_id_,'  перед command_gas') ;
        insert into command_gas (command_type_id, cell_name, rp_id, state, container_barcode)
        values(18, cfull.sname, cfull.repository_part_id,0, cfull.bc);
        obj_rpart.Log(rp_id_,'  после  command_gas') ;
        commit;
        exit;
      end if;
    end loop;
  end if;

  -- теперь заказываем в пустые ячейки
  select count(*) into cnt__ from command_gas where rp_id=rp_id_ and  command_type_id=14 and state not in (2,5);
  obj_rpart.log(rp_id_,'  заказ в пустые '||cnt__);
  if cnt__<=3 then
    for cfull in (select cl.* from cell cl
                  where hi_level_type in (15) and is_full=0 and repository_part_id=rp_id_ and service.is_cell_cmd_locked(cl.id)=0 
                        and is_error=0
                  order by DBMS_RANDOM.random) loop
      obj_rpart.log(rp_id_,'  выбрали ячейку сброса '||cfull.sname);
      lstate:=5;
      for cmd in (select * from command_gas
                  where command_type_id=14 and cell_name=cfull.sname and rp_id=cfull.repository_part_id
                  order by id desc) loop
        lstate:=cmd.state;
        exit;
      end loop;
      if lstate=5 then --последняя команда выполнилась, даем новую
        for cnt in (select * from container where location=1 and cell_id in (select id from cell where repository_part_id=rp_id_)
                    order by DBMS_RANDOM.random) loop
          begin
            obj_rpart.log(rp_id_,'  перед ');
            insert into command_gas (command_type_id, cell_name, rp_id, state, container_barcode)
            values(14, cfull.sname, cfull.repository_part_id,0, cnt.barcode);
            obj_rpart.log(rp_id_,'  после  ');
            commit;
          exception when others then
            obj_rpart.log(rp_id_,'  error:  '||SQLERRM);
          end;
          exit;
        end loop;
      end if;
      exit;
    end loop;
  end if;

end;

-- крэш-тест приемки товара
procedure crash_test_cmd_accept(cell_name_ varchar2, rp_id_ number) is -- крэш-тест приемки товара
begin
  for cc in (select * from cell where sname=cell_name_ and repository_part_id=rp_id_ and hi_level_type in (16,9) and is_full=0) loop
    for cnt in (select * from container cnt
                where location=0
                  and not exists (select * from container_content where container_id=cnt.id and quantity >0))  loop
      begin
        insert into sarmat.command_gas (command_type_id,rp_id, container_barcode ,content, cell_name)
        values(11,rp_id_, cnt.barcode,'[9534273;67]',cell_name_) ;
        commit;
      exception when others then
        return;
      end;
      exit;
    end loop;
  end loop;
end;

-- возвращает огурец, на котором послежний раз хрнаился товар
function get_container_last_rp(container_barcode_ varchar2) return number is
  max_id_ number;
  cont_id_ number;
begin
    select id into cont_id_ from container where barcode=container_barcode_;
    select nvl(max(id),0) into max_id_ from command_gas where container_id=cont_id_ and nvl(rp_id,0)>0;
    for cg in (select * from command_gas where id=max_id_) loop
        return cg.rp_id;
    end loop;
    return null;
end;

-- парсит строку товара в таблицу
procedure parse_cg_cc(cg_id in number, ccont in varchar2, cmgd in number) is
  s varchar2(4000);
  ss varchar2(4000);
  sgd varchar2(100);
  sgdr varchar2(100);
  sn varchar2(4000);
  snotes varchar2(4000);
  scnt number;
  cnt number;
  cntg number;
  IAEC number;

  ipc number(1);
  gdp_id_ varchar2(100);
  sn1 varchar2(250);

begin
  select nvl(is_party_calc,0), is_allow_store_empty_cnt into ipc, IAEC from repository;
  delete from command_gas_container_content where command_gas_id=cg_id;
  -- разбор строки состава принимаемого контейнера
  s:=trim(ccont);
  --begin
    loop
       if substr(s,1,1)<>'[' then
         raise_application_error(-20070,'<content> has bad structure! substr(s,1,1)<>[');
       end if;
       cnt:=instr(s,']');
       ss:=substr(s,2,cnt-2); -- текущая позиция
       scnt:=instr(ss,';'); -- первый ";"
       if scnt=0 then
         raise_application_error(-20070,'<content> has bad structure! scnt=0');
       end if;
       sgd:=substr(ss,1,scnt-1);
       sn:=substr(ss,scnt+1);
       scnt:=instr(sn,';');
       if scnt<>0 then -- есть комментарий
         --dbms_output.put_line('1-й '||scnt);
         sn1:=substr(sn,scnt+1); -- означили что после кол-ва
         sn:=substr(sn,1,scnt-1)  ; -- Означили кол-во
         scnt:=instr(sn1, ';');
         --dbms_output.put_line('2-й ' ||scnt);
         --dbms_output.put_line(sn1||'-'||sn);
         if scnt<>0 then
           snotes:=substr(sn1,1,scnt-1);
           gdp_id_:=substr(sn1,scnt+1);
         else
           snotes:=sn1;
           gdp_id_:='';
         end if;
         --        raise_application_error(-20070,sn);
       else -- нет комментария и ничего
         snotes:='';
         gdp_id_:='';
       end if;
       /*if nvl(to_number(sn),0)=0  then -- нулевое кол-во при приеме
         if  IAEC<>1 then
           raise_application_error(-20070,'Empty quantity for parse_content');
         end if;
         exit;
       else*/
         select count(*) into cntg from good_desc where trim(upper(id))=trim(upper(sgd));
         if cntg=0 then
             raise_application_error(-20070,'Good_desc with ID=['||sgd||'] does''nt exist!');
         end if;
         select id into sgdr from good_desc where trim(upper(id))=trim(upper(sgd));
         if ipc=0 and gdp_id_ is not null then
             raise_application_error(-20070,'Calculation in parts is disabled!');
         end if;
         insert into command_gas_container_content  (command_gas_id, gd_id, qty, notes, gdp_id)
         values(cg_id,sgdr,to_number(sn),snotes, gdp_id_);
         dbms_output.put_line('Вставка '||cg_id||' '||sgdr||' '||to_number(sn)||' '||snotes||' '|| gdp_id_);
         if cnt>=length(s) then
           exit;
         else
           s:=substr(s,cnt+1);
           if cmgd=0 then
             raise_application_error(-20070,'In <content> must be one good_desc!');
           end if;
         end if;
         exit when s is null;
       --end if;
    end loop;
  --exception when others then
  --  raise_application_error(-20070,'<content> has bad structure or multi_gd not allowed!');
  --end;

end;


-- считает, сколько уже подвезено товара по command_gas
function get_always_out_bcg(cg_id in number, gd_id_ in varchar2, gd_party_id_ number) return number is
  sq_out number;
  sq_now_out number;
begin
  -- уже выдано по команде кол-ва
  select nvl(sum(cooc.quantity),0) into sq_out
  from command_order_out_container cooc, command_order co
  where co.id=cooc.cmd_order_id and co.command_gas_id=cg_id
  and cooc.command_gas_id=cg_id;

  -- везется в контейнерах
  --select nvl(sum(cc.quantity),0)  into sq_now_out
  select /*+RULE*/ nvl(sum(cop.quantity_to_pick),0)  into sq_now_out
  from container_content cc, command c, command_gas_out_container_plan cop
  where c.command_gas_id=cg_id and cc.container_id=c.container_id
        and cc.good_desc_id=gd_id_
        and nvl(cc.gdp_id,0) = nvl(gd_party_id_ ,0)
        and cop.container_id=cc.container_id
        and cop.cmd_gas_id=c.command_gas_id
        -- команда незавершена или ячейки целевые не есть ячейки сброса
        and (
         -- либо явно команды в яч. сброса
         (c.state<>5 and IS_INTERMEDIATE=0)
         or
         -- либо в буфер, но до сброса
         (c.state in (0,1,3,5) and IS_INTERMEDIATE=1
          and not exists (select * from command where command_GAS_ID=cg_id
                          and container_id=c.container_id
                          and id<>c.id and IS_INTERMEDIATE=0))
        );

  -- возвращаем сколько уже привезено
  -- service.log2file('          GAS: get_always_out_bcg='||nvl(sq_out+sq_now_out,0)||' sq_out='||sq_out||' sq_now_out='||sq_now_out);
  return nvl(sq_out+sq_now_out,0);
end;

-- сколько штук запланировано к подвозу?
function get_cg_was_cnt_planned(cg_id_ number) return number is
  res number;
begin
  select nvl(sum(quantity_to_pick),0) into res
  from command_gas_out_container_plan where cmd_gas_id=cg_id_;
  return res;
end;


-- высчитать сторону предпочтительную для забора товара
function presence_in_side(cg_id in number, cmd_side in number) return number is
  wm number;
  mnq number;
  cgrec command_gas%rowtype;
  sq_need number;
  sbq number;
begin
  if cmd_side=-1 then -- по фиг какая
    return 0;
  else
    select current_mode into wm from repository;
    select * into cgrec from command_gas where id=cg_id;
    -- считаем, сколько уже по command_gas подвезено, а сколько надо
    sq_need:=cgrec.quantity-get_always_out_bcg(cg_id,cgrec.good_desc_id, cgrec.gd_party_id);
    if sq_need=0 then
      return 0; -- уже все
    else
      sbq:=0;
      for bq in (select cnt_cont.quantity
                 from cell c, container cntr, container_content cnt_cont
                 where
                   c.hi_level_type=1 and zone_id<>0
                   and service.is_cell_over_locked(c.id)=0
                   and cnt_cont.container_id=cntr.id
                   and cnt_cont.good_desc_id=cgrec.good_desc_id
                   and cntr.cell_id=c.id
                 order by get_quantity_accordance(sq_need,wm,cnt_cont.quantity)) loop
        sbq:=bq.quantity;
      end loop;
      for bq in (select cnt_cont.quantity
                 from cell c, container cntr, container_content cnt_cont
                 where
                   c.hi_level_type=1 and zone_id<>0
                   and service.is_cell_over_locked(c.id)=0
                   and cnt_cont.container_id=cntr.id
                   and cnt_cont.good_desc_id=cgrec.good_desc_id
                   and cntr.cell_id=c.id
                   and c.side=cmd_side
                   and cnt_cont.quantity=sbq
                 ) loop
        return 0;
      end loop;
      return 1;
    end if;
  end if;
end;

-- =0 если есть на нужной стороне, 1 - нет
function presence_in_side_accurance(rp_id number, rp_max_npp number,
         cg_id number,cmd_side number,
         rpmode number,q_need number, gd_id varchar2)
  return number is
begin
  if cmd_side=-1 then -- по фиг какая сторона
    return 0;
  else
    for cc in (select c.side
               from cell c, container cn , container_content ccont
               where cn.cell_id=c.id and ccont.good_desc_id=gd_id
                 and c.repository_part_id=rp_id
                 and ccont.container_id=cn.id
                 and (
                     (hi_level_type =1 and zone_id<>0 )or
                     (hi_level_type =7
                      and exists(select * from command_rp
                                 where command_type_id=3
                                   and state in (1,3)
                                   and c.id =cell_src_id
                                   and substate is null))
                     )
                     and service.is_cell_over_locked(c.id)=0
                     order by get_quantity_accordance(q_need,rpmode,ccont.quantity),
                              decode(cmd_side,-1,0,abs(c.side-cmd_side)),
                              obj_rpart.calc_robot_nearest(rp_id, rp_max_npp, c.track_npp)) loop
      if cc.side=cmd_side then
        return 0;
      else
        return 1;
      end if;
    end loop;
  end if;
  -- сюда не должны доходить, но на всякий случай
  return 1;
end;

-- считает параметр для сортировки команд отбора
function get_quantity_accordance(delta in number,rpmode in number,q_cont in number) return number is
begin
  if delta<0 then
     raise_application_error (-20003, 'Ошибка сортировки ячейки для взятия товара', TRUE);
  end if;
  if rpmode=1 then -- макс скорость
    if delta>q_cont then
      -- нужно 10, есть три контейнера 2,5,7 || значения 8, 5, 3
      return (delta-q_cont);
    else
      -- нужно 10, есть три контейнера 12,15,17 || значения -0.5, -0.2, -0.14
      if (q_cont-delta)=0 then
        return - 99999999;
      else
        return -1/(q_cont-delta);
      end if;
    end if;
  else -- макс порядок, ищем минимум
    return q_cont;
  end if;
end;


end obj_cmd_gas;
/
