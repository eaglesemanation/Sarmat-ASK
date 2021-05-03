create or replace package body obj_ask is -- пакет объетка АСК в целом

-- получить имя файла текущего лога
function Get_Log_File_Name return varchar2 is
begin
  return 'ask_ora_'||to_char(sysdate,'ddmmyy')||'.log';
end;

-- запись строки в журнал
procedure Log(txt_ varchar2) is
 file_handle__  utl_file.file_type;
 fn__ varchar2(300);
begin
 fn__:=Get_Log_File_Name;
 file_handle__ := sys.utl_file.fopen('LOG_DIR', fn__, 'A');
 utl_file.put_line(file_handle__, to_char(systimestamp,'hh24:mi:ss.ff')||' '||txt_);
 utl_file.fclose(file_handle__);
end;

-- добавить лог о глобальной ошибке
procedure global_error_log(error_type_ number,repository_part_id_ number,robot_id_ number,errm_ varchar2) is
  rp_id__ number;
  cnt_ number;
begin
  if repository_part_id_ is null and robot_id_ is not null then
    select repository_part_id into rp_id__ from robot where id=robot_id_;
  else
    rp_id__:=repository_part_id_;
  end if;
  select count(*) into cnt_ from error
  where date_time>sysdate-1/(24*60) and error_type_id=error_type_
        and notes=errm_ and nvl(rp_id,0)=nvl(rp_id__,0)
        and nvl(robot_id,0)=nvl(robot_id_,0);
  if cnt_=0 then
    insert into error(date_time,error_type_id,rp_id,robot_id,notes)
    values(sysdate,error_type_,rp_id__,robot_id_,errm_);
    commit;
  end if;
  exception when others then
     Log('Ошибка формирования записи global_error_log:'||SQLERRM);
     null;
end;

-- проверка остатков товара на консистентность
procedure check_gdrest_consistance is
  errm varchar2(1000);
  msg varchar2(1000);
begin
  msg:='  check_gdrest_consistance - начало' ;
  log(msg);

  for rps in (select id from repository where nvl(storage_by_firm,0)=1) loop
    for fgd_cc in (select /*+RULE*/ * from (
                                   select
                                   gd.id gdid,
                                   gd.name gdname,
                                   f.name fname,
                                   f.id firm_id,
                                   (select sum(quantity) from container_content cc, container c
                                    where c.id=container_id and firm_id=f.id and gd.id=good_desc_id
                                          and c.id not in  (select container_id from command_gas
                                                            where command_type_id=11 and state_ind=1)) ccqty,
                                   (select quantity+quantity_reserved qty from firm_gd where firm_id=f.id and gd.id=gd_id) fqty
                                   from firm f, good_desc gd)
                                   where nvl(ccqty,0)<>nvl(fqty,0)) loop
      errm:=' Ошибка сходимости состава контейнеров с остатками по клиентам для '||fgd_cc.gdid||' '||fgd_cc.firm_id||' '||fgd_cc.ccqty||' '||fgd_cc.fqty;
      log(errm );
      raise_application_error (-20003, errm, TRUE);
    end loop;

    for ggd in (select * from (
                  select  id, quantity+quantity_reserved qq,
                     (select nvl(sum(quantity+quantity_reserved),0) from firm_gd where gd_id=gd.id) ss
                  from good_desc gd)
                where qq<>ss) loop
      errm:=' Ошибка сходимости состава остатков с остатками по клиентам для '||ggd.id;
      log(errm );
      raise_application_error (-20003, errm, TRUE);
    end loop;
  end loop;


  for rps in (select id from repository where is_party_calc=0) loop
    for gdch in (select /*+RULE*/ * from (
                    select gd.name, quantity qty, quantity_reserved qty_reserved, id,
                      (select nvl(sum(quantity),0) from command_gas
                       where command_type_id=25 and state=5 and good_desc_id=gd.id ) qpry,
                      (select nvl(sum(cgoo.qty),0) from command_gas cg, command_gas_container_content cgoo
                         where command_type_id=11
                          and (cell_out_name is not null or nvl(CELL_NAME,'-')='Desktop')
                          and state in (1,3,5)
                          and command_gas_id=cg.id and cgoo.gd_id=gd.id ) qpry11,
                      (select nvl(sum(cgoo.qty_delta),0) from command_gas cg, command_gas_container_content cgoo
                         where command_type_id=26 and state in (1,3,5)
                          and command_gas_id=cg.id and cgoo.gd_id=gd.id ) qinv,
                      (select nvl(sum(quantity),0) from command_order
                        where command_type_id=16 and state=5 and good_desc_id=gd.id ) qras,
                      (select nvl(sum(quantity),0) from command_gas
                        where command_type_id=24 and state=5 and good_desc_id=gd.id ) qras24
                    from good_desc gd) chc
                    where chc.qty+qty_reserved<>qpry+qpry11-qras-qras24+qinv
                    ) loop
      errm:=' Ошибка сходимости товара по остаткам '||gdch.id;
      log(errm );
      raise_application_error (-20003, errm, TRUE);
    end loop;
  end loop;

  -- по партиям
  for rps in (select id from repository where is_party_calc=1) loop
    for gdch in (select /*+RULE*/ good_desc_id, quantity, quantity_reserved ,
                 (select sum(qty) from gd_party where gd_id=gd.good_desc_id) gdp_qty,
                 (select sum(qty_reserved) from gd_party where gd_id=gd.good_desc_id) gdp_qty_reserved,
                 (select nvl(sum(quantity ),0) from container_content  where good_desc_id =gd.id
                   and container_id not in
                   (select container_id from command_gas where command_type_id=11 and state_ind=1)) qty_cont_all
                 from good_desc gd
                 where
                   quantity<>(select sum(qty) from gd_party where gd_id=gd.good_desc_id)
                   or
                   quantity_reserved<>(select sum(qty_reserved) from gd_party where gd_id=gd.good_desc_id)
                   or
                   quantity+quantity_reserved<>(select nvl(sum(quantity ),0) from container_content
                      where good_desc_id =gd.id and container_id not in
                   (select container_id from command_gas where command_type_id=11 and state_ind=1 and cell_out_name is null)))
    loop
      errm:=' Ошибка целостности остатков для товара '||gdch.good_desc_id;
      log(errm );
      raise_application_error (-20003, errm, TRUE);
    end loop;


    for gdpch in (select /*+RULE*/ gd_id, gdp.id, qty+ qty_reserved qnt ,
       (select sum(quantity) from container_content where good_desc_id=gd.id and gdp_id=gdp.id) hh
       from gd_party gdp, good_desc gd
       where gdp.gd_id=gd.good_desc_id
        and (qty+ qty_reserved )<>(select nvl(sum(quantity),0) from container_content
         where good_desc_id=gd.id and gdp_id=gdp.id
            and container_id not in
                   (select container_id from command_gas where command_type_id=11 and state_ind=1 and cell_out_name is null)))
    loop
      errm:= 'Ошибка целостности остатков для партии товара '||gdpch.gd_id;
      log(errm );
      raise_application_error (-20003, errm, TRUE);
    end loop;
  end loop;

  msg:='  проверили сходимость остатков товара';
  log(msg);
end;

-- служебная - получить № исходной команды сбора товаров
function get_root_cmd_order_number(cid_ number) return varchar2 is
begin
  for co in (select * from command_order where id=cid_) loop
    if nvl(co.cmd_order_id,0)=0 then -- root
      return co.order_number;
    else
      return get_root_cmd_order_number(co.cmd_order_id);
    end if;
  end loop;
end;

-- сформировать историю перемещений заданного контейнера
function Get_Desktop_Container_History(bc_ varchar2) return varchar2 is
  res_ varchar2(4000);
  nn_ varchar2(250);
  enter_char varchar2(3);
  cg_id_ number;
begin
  enter_char:=chr(13)||chr(10);
  for cnt in (select * from container where barcode=trim(bc_)) loop
    res_:='Контейнер с ШК='||cnt.barcode||' id='||cnt.id||enter_char;
    if cnt.location=1 then  -- в ячейках
      for cl in (select * from cell where id=cnt.cell_id) loop
        if cl.hi_level_type not in (12,15) then
          return extend.str_concat(res_,'Находится не на рабочем столе, а в ячейке '||cl.sname||' типа '||cl.hi_level_type);
        end if;
        res_:=extend.str_concat(res_,'Контейнер в ячейке сброса '||cl.sname||enter_char);
      end loop;
    else
      res_:=extend.str_concat(res_,'Контейнер за пределами АСК'||enter_char);
    end if;

    for cc in (select * from container_content where container_id=cnt.id and quantity>0) loop
      res_:=extend.str_concat(res_,'  в контейнере gd_id='||cc.good_desc_id||' qty='||cc.quantity||enter_char);
      for gd in (select * from good_desc where id=cc.good_desc_id) loop
        res_:=extend.str_concat(res_,'    в карточке товара qty='||gd.quantity||' qty_reserved='||gd.quantity_reserved||enter_char);
      end loop;
    end loop;
    res_:=res_||enter_char;

    for cmdg in (select c.id cmd_id, crp.id crp_id, ci.id ci_id, command_to_run, ci.date_time_create ci_date_time_create, cg.*
                 from command c, command_gas cg , command_rp crp, command_inner ci
                 where c.container_id=cnt.id and command_gas_id=cg.id and crp.command_id=c.id and ci.command_rp_id=crp.id
                 order by ci.id desc) loop
      cg_id_:=cmdg.id;
      res_:=extend.str_concat(res_,'Приехал по команде command_gas id='||cmdg.id||' good_desc_id='||cmdg.good_desc_id||' qty='||cmdg.quantity||' reserved='||cmdg.reserved||' cmd_state='||cmdg.state||' dtcr='||to_char(cmdg.date_time_create,'dd.mm.yy hh24:mi:ss')||enter_char);
      res_:=extend.str_concat(res_,'  по команде command id='||cmdg.cmd_id||enter_char);
      res_:=extend.str_concat(res_,'    по команде command_rp id='||cmdg.crp_id||enter_char);
      res_:=extend.str_concat(res_,'     по команде command_inner id='||cmdg.ci_id||' cmd_text='||cmdg.command_to_run||' dtcr='||to_char(cmdg.ci_date_time_create,'dd.mm.yy hh24:mi:ss')||enter_char||enter_char);

      for any_cnt in (select c.barcode from command cmd, container c
                      where cmd.command_gas_id=cmdg.id and cmd.container_id=c.id and c.id<>cnt.id) loop
        res_:=extend.str_concat(res_,'  подвозился еще иной контейнер ='||any_cnt.barcode||enter_char||enter_char);
      end loop;

      for co in (select * from command_order where command_gas_id=cmdg.id order by id)  loop
        if nvl(co.cmd_order_id,0)=0 then
           nn_:=co.order_number;
        else -- дозаказ по дефициту
           nn_:='дозаказ дефицита по '||get_root_cmd_order_number(co.cmd_order_id);
        end if;
        res_:=extend.str_concat(res_,'На основании cmd_order id='||co.id||' number_='||nn_||' qty='||co.quantity||' qty_promis='||co.quantity_promis||' state='||co.state||' dtcr='||to_char(co.date_time_create,'dd.mm.yy hh24:mi:ss')||enter_char);
        for cc in (select ccc.*, cc.state, cc.date_time_begin, cc.container_barcode
                   from container_collection cc, container_collection_content ccc
                   where ccc.cc_id=cc.id and cmd_order_id=co.id) loop
          res_:=extend.str_concat(res_,'  container_collection id='||cc.cc_id||'  cont_barcode='||cc.container_barcode ||' state='||cc.state||' dtb='||to_char(cc.date_time_begin,'dd.mm.yy hh24:mi:ss')||enter_char);
          res_:=extend.str_concat(res_,'    container_collection_content qty_need='||cc.quantity_need||' qty_real='||cc.quantity_real||' qty_deficite='||cc.quantity_deficit||enter_char);
        end loop;
      end loop;

      exit; -- берем только последнюю команду
    end loop;

    return res_;
  end loop;
  return 'Контейнер не найден';
end;

-- Переключить АСК в режим <Работает>
procedure To_Work is
begin
  Change_Work_Status(1);
end;

-- Переключить АСК в режим <Пауза>
procedure To_Pause is
begin
  Change_Work_Status(0);
end;

-- Переключить АСК в указанный режим 
procedure Change_Work_Status(new_state_ number) is
begin
  Log('Пришло смена состояния АСК на '||new_state_);
  if new_state_=0 then
    update sarmat.repository set is_work = 0 where is_work <> 0;
  elsif new_state_=1 then
    update sarmat.repository set is_work = 1, LAST_SARMAT_TIMER=sysdate where is_work <> 1;
  elsif new_state_=3 then
    update sarmat.repository set is_work = 3, LAST_SARMAT_TIMER=sysdate where is_work <> 3;
  else
    Log('ERROR - пришло недопустимое новое состояние АСК');
  end if;
  if SQL%ROWCOUNT>0 then
    Log('  состояние АСК сменилось успешно');
  else
    Log('  нет нужды менять состояние');
  end if;
  commit;
end;

-- получить состояние всего АСК
function Get_Work_Status return number is
  res number;
begin
  select is_work into res from repository;
  return res;
end;

-- очистить список стеллажей для перерисовки
procedure Shelving_Need_Redraw_Clear is
begin
  delete from shelving_need_to_redraw;
  commit;
end;

-- очистить список стеллажей для перерисовки (но не более чем заданное ID)
procedure Shelving_Need_Redraw_Clear(max_id_ number) is
begin
  delete from shelving_need_to_redraw where id<=max_id_;
  commit;
end;

-- функция, которая вызывается из таймера для всего склада
procedure Form_Commands is
begin
  Log('');
  Log('*********************************');
  Log('Новый такт');
  -- для сервера заказов
  for rep in  (select * from repository where abstract_level>=4) loop
    obj_cmd_order.Form_Commands;
    Log('  obj_cmd_order.Form_Commands is ok');
  end loop;
  -- для товарного и сервера контейнеров
  obj_cmd_gas.Form_Commands;
  Log('  obj_cmd_gas.Form_Commands is ok');
end;

-- не заблокирована ли ячейка командами?
function Is_Cell_Locked_By_Cmd(cid number) return number is
  cnt number;
  crec cell%rowtype;
begin
  select count(*) into cnt from cell_cmd_lock where cell_id=cid;
  if cnt=0 then
    return 0;
  else
    select * into crec from cell where id=cid;
    if cnt>=crec.max_full_size then
      return 1;
    else
      return 0;
    end if;
  end if;

end;

-- берем максимальный текущий приоритет команд
function get_cur_max_cmd_priority return number is
  cnt number;
  res number;
begin
  select count(*) into cnt from command
  where state in (0,1,3) and command_type_id=1
        and priority<0 and priority>-1000;
  if cnt=0 then -- нет запущенных команд
    select nvl(max(priority),0) into res from command
    where command_type_id=1 and date_time_create>=trunc(sysdate) and priority<0 and priority>-1000;
    return res;
  else
    select nvl(max(priority),0) into res from command
    where command_type_id=1 and state in (0,1,3) and priority<0 and priority>-1000;
    return res;
  end if;
end;

-- установить команду к выполнению
procedure Set_Command(command_gas_id_ number, command_type_id_ number ,
                      rp_src_id_ number, cell_src_sname_ varchar2,
                      rp_dest_id_ number, cell_dest_sname_ varchar2,
                      priority_ number, container_id_ number) is
begin
  Log('Ставим команду на выполнение command_gas_id_='||command_gas_id_ ||' command_type_id_='||command_type_id_||
                    ' rp_src_id_='||rp_src_id_ ||' ell_src_sname_='||cell_src_sname_||
                    ' rp_dest_id_='||rp_dest_id_ ||' cell_dest_sname_='|| cell_dest_sname_ ||
                    ' priority_='||priority_ ||' container_id_='|| container_id_ );
  insert into command (command_gas_id,command_type_id, rp_src_id, cell_src_sname,
                         rp_dest_id, cell_dest_sname, priority, container_id)
  values(command_gas_id_,command_type_id_,
         rp_src_id_, cell_src_sname_,
         rp_dest_id_, cell_dest_sname_,
         priority_, container_id_);
  if nvl(container_id_,0)>0 then
    update container set cell_goal_id=obj_rpart.get_cell_id_by_name(rp_dest_id_,cell_dest_sname_)
    where id=container_id_;
  end if;
end;

-- взять ШК контейера по его ID
function Get_Cnt_BC_By_ID(cnt_id_ number) return varchar2 is
begin
  for cc in (select * from container where id=nvl(cnt_id_,0)) loop
    return cc.barcode;
  end loop;
  return ' ';

end;

-- получить имя всего АСК
function Get_ASK_name return varchar2 is
begin
  for rr in (select * from repository) loop
    return rr.name;
  end loop;
end;

-- сформировать в файле cmd_err.csv отчет по ошибкам команд роботов
procedure Gen_Cmd_Err_Rep is
 file_handle__  utl_file.file_type;
 fn__ varchar2(300);
begin
  fn__:='cmd_err.csv';
  file_handle__ := sys.utl_file.fopen('LOG_DIR', fn__, 'W');
  utl_file.put_line(file_handle__, 'Sklad;CMD ID;DTime;cmd;container;cell;p-type;');
  for cer in (select
      rp.name sklad, t.id, to_char(date_time_begin,'dd.mm.yy hh24:mi') date_time_begin, command_to_run, obj_ask.get_cnt_bc_by_id(container_id) container, nvl(cell_src_sname, cell_dest_sname) cell,
      (select short_name from problem_resolving where id=problem_resolving_id) ptype
      from sarmat.command_inner t , sarmat.repository_part rp
      where state=2 and rp.id=t.rp_id
      order by date_time_create ) loop

      utl_file.put_line(file_handle__, cer.sklad||';'||cer.id||';'||cer.date_time_begin||';"'||cer.command_to_run||'";"'||cer.container||'";'||cer.cell||';'||cer.ptype||';');
  end loop;
 utl_file.fclose(file_handle__);
end;

-- можно ли принимать команды от внешней системы?
function is_can_accept_cmd return number is
begin
   for rr in (select id from repository where is_work=0) loop
     if service.get_rp_param_number('accept_cmd_always',0)=1 then
       return 1;
     else
       return 0;
     end if;
   end loop;
   return 1;
end;

-- можно ли принять на подсклад данный контейнер?
function is_enable_container_accept(rp_id_ number, cnt_id_ number) return number is
  i_ number;
begin
 if obj_rpart.is_exists_cell_type(rp_id_,obj_ask.CELL_TYPE_TR_CELL)=0 and obj_rpart.is_exists_cell_type(rp_id_,obj_ask.CELL_TYPE_TR_CELL_OUTCOMING)=0 then
   -- вариант, когда склад обособленный
   for cnt in (select * from container where id=cnt_id_) loop
     select count(*) into i_ from cell
     where repository_part_id=rp_id_ and hi_level_type=CELL_TYPE_STORAGE_CELL and is_error=0 and is_full=0
           and cell_size<=cnt.type
           and not exists (select * from cell_cmd_lock where cell_id=cell.id);
     if i_=0 then
       return 0;
     end if;
   end loop;
 end if;
 return 1;
end;

-- берем максимальный приоритет команд на указанном подскладе
function get_cmd_max_priority(rp_id_ number) return number is
  cnt number;
  res number;
begin
  select count(*) into cnt from command
  where state in (0,1) and command_type_id=1 and rp_src_id =rp_id_ and date_time_begin is null;
  if cnt=0 then -- нет запущенных команд
    return 0;
  else
    select nvl(max(priority),0) into res from command
    where command_type_id=1 and state in (0,1) and rp_src_id=rp_id_ and date_time_begin is null;
    return res;
  end if;
  return 0;

  exception when others then
    return 0;
end;

-- сформировать отчет о нагрузке на АСК за последнюю неделю (отчет служебный, выводится в dbms_output)
procedure workload_info is
  last_dt date;
  res number;
begin
  last_dt:=trunc(sysdate)-14;
  dbms_output.put_line(to_char(sysdate,'dd.mm.yy'));
  dbms_output.put_line('Нагрузка за последние две недели');
  select count(*) into res from command_rp where date_time_create>=last_dt;
  dbms_output.put_line('Всего команд перемещения контейнеров: '||res);
  for rr in (select * from repository_part order by id ) loop
    select count(*) into res from command_rp where date_time_create>=last_dt and rp_id=rr.id;
    dbms_output.put_line('  из них по складу '||rr.id||': '||res);
  end loop;
  
  dbms_output.put_line('');

  select count(*) into res from command_inner where date_time_create>=last_dt and date_time_end is null;
  dbms_output.put_line('Всего ошибок команд перемещения контейнеров: '||res);
end workload_info;

-- получить имя ячейки
function get_cell_name(pcell_id in number, with_notes number default 0) return varchar2 is
  result cell.sname%type;
begin
  if with_notes=0 then
    select c.sname into result from cell c where c.id = pcell_id;
    return result;
  else
    for  cc in (select * from cell where id = pcell_id) loop
      if cc.notes is not null then
        return (cc.sname ||'-'||cc.notes);
      else
        return cc.sname;
      end if;
    end loop;
  end if;
  return null;
exception
  when others then
    return null;
end;


-- вычисляет расстояние между двумя треками npp
function calc_distance(rp_type number, max_npp number, n1 number, n2 number) return number is
  res number;
  nn1 number;
  nn2 number;
begin
  if n2<n1 then
    nn1:=n2;
    nn2:=n1;
  else
    nn1:=n1;
    nn2:=n2;
  end if;
  res:=nn2-nn1;
  if rp_type=1 then -- только для кольцевого
    if max_npp-nn2+nn1<res then
      res:=max_npp-nn2+nn1;
    end if;
  end if;
  return res;
end;

-- вычисляем расстояние по направлению
function calc_distance_on_way(rp_type number, max_npp number, n1 number, n2 number, dir_ in number) return number is
  res number;
  nn1 number;
  nn2 number;
begin
  if dir_=1 then -- по часовой
    if n2>n1 then
      res:=n2-n1;
    else
      if rp_type=1 then -- кольцевой
        res:=max_npp-n1+n2;
      else
        res:=extend.infinity;
      end if;
    end if;
  else -- против
    if n2<n1 then
      res:=n1-n2;
    else
      if rp_type=1 then -- кольцевой
        res:=max_npp-n2+n1;
      else
        res:=extend.infinity;
      end if;
    end if;
  end if;
  return res;
end;

-- получить числовой ID товара по символьному ID
function get_good_desc_id_by_id(gdid_ varchar2) return number is
  res number;
begin
  select good_desc_id into res from good_desc where id=gdid_;
  return res;
end;

-- высчитать заполненность стеллажа
function get_shelving_fullness(shelv_id in number) return number is
  res number;
  ff number;
  ee number;
begin
  res:=0;
  begin
    select nvl(sum(is_full),0) into ff
    from cell where shelving_id = shelv_id
                    and hi_level_type not in (11,13);
    select nvl(sum(max_full_size),0) into ee
    from cell where shelving_id = shelv_id
                    and hi_level_type not in (11,13);
    res:=ff/(ee);
    if res>1 then
      res:=1;
    elsif res<0 then
      res:=0;
    end if;
    return res;
  exception when others then
    return res;
  end;
end;


end obj_ask;
/
