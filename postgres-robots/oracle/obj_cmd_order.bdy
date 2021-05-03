create or replace package body obj_cmd_order is

function get_container_izlish(cnt_id_ in number, gd_id_ in varchar2, gd_party_id_ number) return number is
  cc_id_ number;
  sqn number;
  qncnt number;
begin
  select id into cc_id_ from container_collection
  where state=0 and container_id=cnt_id_;
  -- считаем сколько еще к отбиранию
  select
    nvl(sum(ccc.quantity_need-(ccc.quantity_real+ccc.quantity_deficit)),0) into sqn
  from  container_collection_content ccc
  where ccc.cc_id=cc_id_ and good_desc_id=gd_id_ and nvl(gd_party_id_,0)=nvl(gd_party_id,0);
  -- считаем реальный остаток
  select quantity into qncnt
  from container_content where container_id=cnt_id_ and good_desc_id=gd_id_ and nvl(gdp_id,0)=nvl(gd_party_id_,0);
  if qncnt>sqn then
    return qncnt-sqn;
  else
    return 0;
  end if;
end;


procedure add_to_cg_plan(cg_id number,qnt_ number, co in command_order%rowtype) is
  new_qtp number;
  qnt number;
  qoc number;
begin
  qnt:=qnt_;
  for cgp in (select * from command_gas_out_container_plan
              where cmd_gas_id =cg_id and quantity_to_pick <quantity_all
              order by quantity_all-quantity_to_pick) loop
   exit when qnt=0;
   if qnt<=cgp.quantity_all-cgp.quantity_to_pick then
     new_qtp:=cgp.quantity_to_pick+qnt;
     qoc:=qnt;
     qnt:=0;
   else
     new_qtp:=cgp.quantity_all;
     qoc:=cgp.quantity_all-cgp.quantity_to_pick;
     qnt:=qnt-(cgp.quantity_all-cgp.quantity_to_pick);
   end if;
   update command_gas_out_container_plan
   set quantity_to_pick=new_qtp
   where cmd_gas_id =cg_id and cgp.container_id=container_id;

   -- теперь смотрим - а не числится ли этот контейнер среди уже привезенных
   for prk in (select * from command_gas_out_container
               where cmd_gas_id=cgp.cmd_gas_id
                 and container_id=cgp.container_id) loop
     -- числится таки
     obj_ask.log('add_to_cg_plan: уже есть подвезенный контейнер с которого можно взять чуток '||qoc||'. container='||prk.container_id);
     begin
       insert into command_order_out_container (cmd_order_id, container_id, container_barcode,
         good_desc_id, quantity, order_number, group_number,
         cell_name,
         point_number, gd_party_id)
       values (co.id,prk.container_id, prk.container_barcode,
         prk.good_desc_id, qoc, co.order_number, co.group_number,
         prk.cell_name ,
         co.point_number, co.gd_party_id);
     exception when others then
       obj_ask.log('SORD: add_to_cg_plan - ошибка добавления - уже добавлено?');
     end;
     -- вот тут наверное проверка, а не покрыли ли полностью все что нужно, и не надо ли state=5 делать у command_order???
     -- if qoc=co.quantity then
     -- или правильней в form_command в sorder проверить - нет ли команд, что уже пора закрывать?
   end loop;
  end loop;
end;

procedure Order_Content_Out_Doz_on_dfct is
  cor number;
  qqq number;
begin
 if service.get_rp_param_number('Order_Content_Out_Doz_on_dfct',0)=1 then
   for rep in  (select * from repository where nvl(is_party_calc,0)=0 and nvl(storage_by_firm,0)=0) loop -- только если склад не по партиям и не по фирмам
     for dzk in (select t.id cmd_order_id, t.good_desc_id,quantity_promis, obj_cmd_order.get_Order_Content_Out_Picked(t.id) picked , COMMAND_GAS_ID,
                        t.cmd_order_id cor, gd.quantity gd_quantity,
                        rp_id,cell_name, order_number, group_number
                 from command_order t , good_desc gd
                 where state=5 and command_type_id=15
                   and obj_cmd_order.get_Order_Content_Out_Picked(t.id)<>quantity_promis -- только реальный <> обещанный
                   and obj_cmd_order.get_Order_Content_Out_Picked(t.id,1)=quantity_promis  -- реальный + дефицит = обещанный
                   and date_time_create>sysdate-3
                   and gd.id=t.good_desc_id
                   and date_time_end is null -- еще не помечена как завершенная
                   and gd.quantity>0
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id=t.id) -- не создан повторный
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id<>0 and cmd_order_id=t.cmd_order_id and id>t.id) -- не создан цепочка
                 order by t.id desc) loop
          if dzk.gd_quantity=0 then
            update command_order set date_time_end=sysdate where id=dzk.cmd_order_id; -- типа закончили с этой командой
          else
            if dzk.gd_quantity>=dzk.quantity_promis-dzk.picked then
              qqq:=dzk.quantity_promis-dzk.picked;
            else
              qqq:=dzk.gd_quantity;
            end if;
            for cg in (select * from command_gas where id=dzk.command_gas_id and state=5) loop -- только для дозаверешенных
              if dzk.cor=0 then
                cor:=dzk.cmd_order_id;
              else
                cor:=dzk.cor;
              end if;
              insert into command_order(command_type_id, cmd_order_id, quantity, good_desc_id,rp_id,cell_name)
              values(15, cor,qqq,dzk.good_desc_id,dzk.rp_id,dzk.cell_name);
            end loop;
          end if;
      end loop;
    end loop;

    -- отбор завершен, наличия на складе нет
    for otf in (select t.id cmd_order_id, t.good_desc_id,t.quantity, quantity_promis, obj_cmd_order.get_Order_Content_Out_Picked(t.id) picked , COMMAND_GAS_ID,
                        t.cmd_order_id cor, gd.quantity gd_quantity,
                        rp_id,cell_name, order_number, group_number
                 from command_order t , good_desc gd
                 where state in (5,2) and command_type_id=15
                   and t.quantity<>quantity_promis
                   and obj_cmd_order.get_Order_Content_Out_Picked(t.id)=quantity_promis
                   and date_time_create>sysdate-5
                   and gd.id=t.good_desc_id
                   and gd.quantity+gd.quantity_reserved=0
                   and date_time_end is null -- еще не завершенная
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id=t.id) --  не создан повторный
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id<>0 and cmd_order_id=t.cmd_order_id and id>t.id) -- не создан цепочка
                 order by t.id desc) loop
      update command_order set date_time_end=sysdate where id=otf.cmd_order_id; -- типа закончили с этой командой
    end loop;

    -- отбор завершен, наличия на складе нет, но деифицит реально есть, а promis в command_order не исправлен
    for otf in (select  t.id cmd_order_id, t.good_desc_id,t.quantity, quantity_promis, obj_cmd_order.get_Order_Content_Out_Picked(t.id) picked , COMMAND_GAS_ID,
                        t.cmd_order_id cor, gd.quantity gd_quantity,
                        rp_id,cell_name, order_number, group_number
                 from command_order t , good_desc gd
                 where state in (5) and command_type_id=15
                   and t.quantity=quantity_promis
                   and obj_cmd_order.get_Order_Content_Out_Picked(t.id,1)=quantity_promis
                   and obj_cmd_order.get_Order_Content_Out_Picked(t.id,2)>0
                   and date_time_create>sysdate-2
                   and gd.id=t.good_desc_id
                   and gd.quantity+gd.quantity_reserved=0
                   and date_time_end is null -- еще не завершенная
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id=t.id) --  не создан повторный
                   and not exists (select * from command_order where command_type_id=15 and cmd_order_id<>0 and cmd_order_id=t.cmd_order_id and id>t.id) -- не создан цепочка
                 order by t.id desc) loop
      update command_order set date_time_end=sysdate where id=otf.cmd_order_id; -- типа закончили с этой командой
    end loop;


    -- помечаем как законченные те команды, что успешно доподвезлись
    for ce in (select t.id, sum(quantity_need)-sum(quantity_real), sum(quantity_real), t.quantity
                 from command_order t , container_collection_content ccc
                 where state=5 and command_type_id=15
                   and date_time_create>sysdate-3
                   and ccc.cmd_order_id=t.id
                   and nvl(t.cmd_order_id,0)<>0
                   and date_time_end is null -- еще не помечена как завершенная
                   and not exists (select * from command_order where command_type_id=15 and id<>t.id and cmd_order_id in (t.id, t.cmd_order_id)) -- не создан повторный
              group by t.id, t.quantity
              having sum(quantity_need)-sum(quantity_real)=0 and sum(quantity_real)=t.quantity) loop
      update command_order set date_time_end=sysdate where id=ce.id; -- типа закончили с этой командой
    end loop;
 
  end if;
end;

function get_Order_Content_Out_Picked(cmd_order_id_ number, deficite_type_ number default 0) return number is -- сколько по cmd_order уже отоьрано оператором
  res number;
begin
  if deficite_type_=1 then  -- реальный+дефицит
    select nvl(sum(quantity_real),0)+nvl(sum(quantity_deficit),0) into res from container_collection_content where cmd_order_id=cmd_order_id_;
  elsif deficite_type_=0 then -- только реальный
    select nvl(sum(quantity_real),0) into res from container_collection_content where cmd_order_id=cmd_order_id_;
  elsif deficite_type_=2 then  -- дефицит только
    select nvl(sum(quantity_deficit),0) into res from container_collection_content where cmd_order_id=cmd_order_id_;
  end if;
  return nvl(res,0);
end;


function get_Order_Content_Out_Promis(cmd_order_id_ number) return number is
  res number;
begin
  select nvl(sum (quantity_promis - obj_cmd_order.get_Order_Content_Out_Picked(co.id,2)),0) prm
  into res
  from command_order co
  where cmd_order_id_ in (id, cmd_order_id) and command_type_id=15;
  return res;
end;


procedure Form_Commands is
  cnt number;
  cmd_id  number;
  cg_rec command_gas%rowtype;
  qnt_need number;
  qnt_izlish number;
  qnt number;
  rrec repository%rowtype;
  ppid number;
begin
  obj_ask.log('obj_cmd_order.Form_Commands: НАЧАЛО');

  Order_Content_Out_Doz_on_dfct;
  obj_ask.log('obj_cmd_order.Form_Commands: дозаказ после дефицита');

  -- проверяем, нет ли уже выполненных команд поставки, но у которых есть пометка, что они не выполнены
  for nm in (select co.id, co.quantity, nvl(sum(cooc.quantity ),0) sumq , nvl(sum(ccc.quantity_real  ),0) sumcc
             from command_order co, command_order_out_container cooc, container_collection cc, container_collection_content ccc
             where command_type_id=15 and cooc.cmd_order_id=co.id and co.state in (1,3) and cc.cmd_gas_id=co.command_gas_id
             and ccc.cc_id=cc.id and ccc.cmd_order_id=co.id and cc.container_id=cooc.container_id
             and nvl(co.gd_party_id,0)=nvl(cooc.gd_party_id,0) and nvl(co.gd_party_id,0)=nvl(ccc.gd_party_id,0)
             group by co.id, co.quantity
             having co.quantity= nvl(sum(ccc.quantity_real ),0)) loop
    obj_ask.log('SORD: есть command_order выполненная, но помеченная как невыполненная с id='||nm.id);
    update command_order set state=5 where id=nm.id;
    commit;
  end loop;

  select * into rrec from repository;
  for co in (select * from command_order where state=0 order by id) loop
    obj_ask.log('SORD: есть еще нераспределенная команда сервера заказов с id='||co.id);
    -------------------
    -- Order.Content.Out
    -------------------
    if co.command_type_id=15 then
      obj_ask.log('  SORD: тип=15');

      -- резервирование
      if rrec.storage_by_firm=1 then -- проверка на наличие по фирме
        -- пытаемся резервировать
        select quantity into qnt from firm_gd where gd_id=co.good_desc_id and firm_id=co.firm_id;
        if qnt=0 then
          -- не можем зарезервировать
          update command_order set state=2, quantity_promis=0 where id=co.id;
        else
          -- резервируем
          if qnt>=co.quantity then
            qnt:=co.quantity;
          end if;
          update firm_gd
          set quantity_reserved=quantity_reserved+qnt, quantity=quantity-qnt
          where gd_id=co.good_desc_id and firm_id=co.firm_id;
          update command_order set quantity_promis=qnt where id=co.id;
        end if;

      elsif nvl(rrec.is_party_calc,0)=1 then -- учет по партиям
        for gg in (select * from good_desc where id= co.good_desc_id) loop
          if nvl(co.gd_party_id,0)=0 then
            select id into ppid from gd_party where gd_id=gg.good_desc_id and pname is null;
          else
            ppid:=co.gd_party_id;
          end if;
          -- пытаемся резервировать
          obj_ask.log('SORD: попытка резервирования партии gg.good_desc_id='||gg.good_desc_id||' ppid='||ppid);
          select qty into qnt from gd_party where gd_id=gg.good_desc_id and ppid=id; ---qty_reserved
          obj_ask.log('SORD: qnt='||qnt||' co.quantity='||co.quantity);
          if qnt<=0 then
            -- не можем зарезервировать
            update command_order set state=2, quantity_promis=0 where id=co.id;
          else
            -- резервируем
            if qnt>=co.quantity then
              qnt:=co.quantity;
            end if;
            update gd_party
            set qty_reserved=qty_reserved+qnt, qty=qty-qnt
            where gd_id=gg.good_desc_id and id=ppid;
            update command_order set quantity_promis=qnt where id=co.id;
          end if;
        end loop;
      else -- учет товаров общий
        -- пытаемся резервировать
        select quantity into qnt from good_desc where id=co.good_desc_id;
        if qnt=0 then
          -- не можем зарезервировать
          update command_order set state=2, quantity_promis=0 where id=co.id;
        else
          -- резервируем
          if qnt>=co.quantity then
            qnt:=co.quantity;
          end if;
          update good_desc
          set quantity_reserved=quantity_reserved+qnt, quantity=quantity-qnt
          where id=co.good_desc_id;
          update command_order set quantity_promis=qnt where id=co.id;
        end if;
      end if;

      if qnt>0 then
        begin
          select * into cg_rec from command_gas cg
          where cg.command_type_id=12 and state in (0,1,3)
                and good_desc_id=co.good_desc_id and priority=-co.group_number
                and nvl(GD_PARTY_ID,0)=nvl(co.GD_PARTY_ID,0)
                and rp_id=co.rp_id and cell_name=co.cell_name and rownum=1;

          -- нашли - уже сформировано command_gas
          obj_ask.log('  SORD: есть command_gas куда приткнуться id='||cg_rec.id);
          update command_gas set quantity=quantity+qnt
          where id=cg_rec.id;
          if cg_rec.state=3 then -- еще надо формировать по команде
            update command_gas set state=1 where id=cg_rec.id;
          end if;
          update command_order set command_gas_id=cg_rec.id, state=1,
                 QUANTITY_FROM_GAS=qnt
          where id=co.id;
          add_to_cg_plan(cg_rec.id,qnt,co);

        exception when others then
          -- не нашли - еще нет ничего
          obj_ask.log('  SORD: нету command_gas куда приткнуться - вначале ищем а нет ли уже готовых. при этом qnt='||qnt);
          -- вначале смотрим - а не открыть ли коллекцию по имеющемуся в соотв. ячейки контейнеру ?
          for coll in (select distinct c.id, ccnt.good_desc_id, c.barcode,
                              cl.sname, ccnt.gdp_id gd_party_id,
                              c.cell_id
                       from container c, container_content ccnt, cell cl
                       where
                         ccnt.container_id=c.id
                         and not exists (select * from container_collection cc where cc.container_id=c.id and state=0)
                         and ccnt.good_desc_id=co.good_desc_id
                         and nvl(ccnt.gdp_id,0)=nvl(co.gd_party_id,0)
                         and ccnt.quantity >0
                         and cl.id=c.cell_id and trim(upper(cl.notes))=trim(upper(co.comp_name))) loop
             insert into container_collection (container_id,CMD_GAS_ID,CONTAINER_BARCODE,CELL_NAME)
             values(coll.id, 0, coll.barcode, coll.sname);
          end loop;
          -- а теперь смотрим - не стоит ли открыть состав коллекции по имеющейся коллекции
          for acc in (select cc.id from container_collection cc,
                        container c, container_content ccnt, cell cl
                      where
                         ccnt.container_id=c.id
                         and cc.state=0 and cc.container_id=c.id
                         and not exists ( select * from container_collection_content ccc
                                          where
                                            ccc.cc_id=cc.id and ccc.good_desc_id=co.good_desc_id
                                            and nvl(ccc.gd_party_id,0)=nvl(co.gd_party_id,0)
                                        )
                         and ccnt.good_desc_id=co.good_desc_id
                         and nvl(ccnt.gdp_id,0)=nvl(co.gd_party_id,0)
                         and ccnt.quantity >0
                         and cl.id=c.cell_id and trim(upper(cl.notes))=trim(upper(co.comp_name))) loop
            insert into container_collection_content (cc_id, cmd_order_id, quantity_need, quantity_real,
                   quantity_deficit, good_desc_id, gd_party_id)
            values(acc.id, 0, 0, 0,0, co.good_desc_id, co.gd_party_id); -- добавляем путую команду чтоб был отбор
          end loop;
          -- смотрим, есть ли контейнер в местах отбора, у которых можно стянуть немного
          qnt_need:=qnt;
          for cics in (select distinct c.id, ccnt.good_desc_id, c.barcode,
                              cc.cell_name, ccnt.gdp_id gd_party_id,
                              c.cell_id
                       from container c, container_collection cc, container_collection_content ccc,
                            container_content ccnt, cell cl
                       where
                         c.id=cc.container_id
                         and ccnt.container_id=c.id
                         and state=0
                         and ccnt.quantity >0
                         and ccc.cc_id=cc.id
                         and ccnt.good_desc_id=co.good_desc_id
                         and nvl(ccnt.gdp_id,0)=nvl(co.gd_party_id,0) and nvl(co.gd_party_id,0)=nvl(ccc.gd_party_id,0)
                         and cl.id=c.cell_id and trim(upper(cl.notes))=trim(upper(co.comp_name))) loop
            obj_ask.log('  SORD: зашли в цикл cnt_id='||cics.id);

            -- если контейнер на рабочем столе или в ячейке закр. за компом команды
            if nvl(cics.cell_id,0)=0 or service.is_cell_on_comp(cics.cell_id,co.comp_name)=1 then
              qnt_izlish:=get_container_izlish(cics.id,cics.good_desc_id, cics.gd_party_id);
              if qnt_izlish>0 then
                obj_ask.log('  SORD: qnt_izlish='||qnt_izlish);
                if qnt_need<=qnt_izlish then -- хватит полностью
                  insert into command_order_out_container (cmd_order_id, container_id, container_barcode,
                    good_desc_id, quantity, order_number, group_number,
                    cell_name,
                    point_number, gd_party_id)
                  values (co.id,cics.id, cics.barcode,
                    cics.good_desc_id, qnt_need, co.order_number, co.group_number,
                    cics.cell_name ,
                    co.point_number, cics.gd_party_id);
                  update command_order set state=5 where id=co.id;
                  obj_ask.log('  SORD: ставим co.state=5');
                  qnt_need:=0;
                else
                  insert into command_order_out_container (cmd_order_id, container_id, container_barcode,
                    good_desc_id, quantity, order_number, group_number,
                    cell_name,
                    point_number, gd_party_id)
                  values (co.id,cics.id, cics.barcode,
                    cics.good_desc_id, qnt_izlish, co.order_number, co.group_number,
                    cics.cell_name ,
                    co.point_number, cics.gd_party_id);
                  qnt_need:=qnt_need-qnt_izlish;
                  update command_order set state=1 where id=co.id;
                end if;
              end if;
            end if;
            exit when qnt_need=0;
          end loop;
          if qnt_need>0 then
            insert into command_gas (command_type_id, priority, cell_name, rp_id, quantity, good_desc_id, reserved, firm_id, gd_party_id, comp_name)
            values(12,nvl(-co.group_number,0), co.cell_name,co.rp_id,qnt_need, co.good_desc_id,1, co.firm_id, co.gd_party_id, co.comp_name)
            returning id into cmd_id;
            obj_ask.log('  SORD: id новой command_gas ='||cmd_id);
            update command_order set command_gas_id=cmd_id , state=1
            where id=co.id;
          end if;
        end;
      end if;
    end if;
  end loop;
  exception when others then
    obj_ask.Log('ERROR - ошибка из cmd_order.Form_Commands: '||SQLERRM);
end;


procedure Cancel_Error_Cmd_Cont_Out(cmd_order_id_ number) is
begin
  for cmd in (select * from command_order where id=cmd_order_id_ and command_type_id=15 and state<>2) loop
    --update command_order set state=2 where id=cmd.id;
    if cmd.state=5 then
      update good_desc set quantity=quantity+cmd.quantity, quantity_reserved=quantity_reserved-cmd.quantity where id=cmd.good_desc_id;
      delete from container_collection_content where cmd_order_id=cmd.id;
      delete from command_order_out_container where cmd_order_id=cmd.id;
    end if;
    commit;
    return;
  end loop;
  raise_application_error (-20003, 'Указанная команда не является пододящей для отмены');
end;

function get_rasdoc_rest(doc_id_ number) return number is
  res number;
  cr number;
begin
  res:=0;
  for dc in (select * from doc_content where doc_id=doc_id_) loop
    --dbms_output.put_line(doc_id_||' good_id='|| dc.good_id||' gdp_id='|| dc.gdp_id||' qty= '||dc.quantity);
    cr:=get_ras_gd_rest(doc_id_, dc.good_id, dc.gdp_id);
    --dbms_output.put_line('    rest='||cr);
    res:=res+cr;
  end loop;
  return res;
end;

function get_ras_gd_rest(doc_id_ number, gd_id_ number, party_id_ number) return number is
  res number;
  was number;
  wasg number;
  idold varchar2(100);
  dd date;
  is_party_c number;
  rparty_id_ number;
  cnt number;
  pname_ varchar2(250);
begin
  select id into idold from good_desc where good_desc_id=gd_id_;
  --dbms_output.put_line('  gd.ID='||idold);
  select is_party_calc into is_party_c from repository;
  if is_party_c=1 then
    if nvl(party_id_,0)<>0 then
      rparty_id_:=party_id_;
    else
      select id into rparty_id_ from gd_party where pname is null and gd_id=gd_id_;
    end if;
    --dbms_output.put_line('  rparty_id_='||rparty_id_);

    if nvl(rparty_id_,0)>0 then
      select pname into pname_ from gd_party where id= rparty_id_;
    else
      pname_:='';
    end if;


    -- смотрим - нет ли нехватки товара
    select count(*) into cnt from command_order where order_number=doc_id_ and good_desc_id=idold
       and gd_party_id=rparty_id_ and state=2;
    if cnt>0 then
      --dbms_output.put_line('  Нехватка товара');
      return 0;
    end if;


    select nvl(sum(quantity),0) into res
    from doc_content
    where doc_id=doc_id_ and good_id=gd_id_ and
           (
           nvl(gdp_id,0)=nvl(party_id_,0)
           or
           pname_ is null and nvl(gdp_id,0)<=0
           );

    --dbms_output.put_line('  res='||res);

    select date_order into dd from doc where id=doc_id_;
    select nvl(sum(quantity),0) into was
    from command_order
    where good_desc_id=idold and nvl(gd_party_id,0)=nvl(rparty_id_,0)
          and command_type_id=16 and order_number =doc_id_ and date_time_create>=dd-30;
    --dbms_output.put_line('  was='||was);
    select nvl(sum(quantity),0) into wasg
    from command_gas
    where good_desc_id=idold and nvl(gd_party_id,0)=nvl(rparty_id_,0)
          and command_type_id=24 and pri_doc_number =doc_id_ and date_time_create>=dd-30;
    --dbms_output.put_line('  wasg='||wasg);

  else
    select sum(quantity) into res
    from doc_content
    where doc_id=doc_id_ and good_id=gd_id_ and nvl(gdp_id,0)=nvl(party_id_,0);
    select date_order into dd from doc where id=doc_id_;
    select nvl(sum(quantity),0) into was
    from command_gas
    where good_desc_id=idold and nvl(gd_party_id,0)=nvl(party_id_,0)
     and command_type_id=24 and pri_doc_number =doc_id_ and date_time_create>=dd-30;
    wasg:=0;

  end if;
  return res-was-wasg;
end;


-- есть ли недостача?
function is_rashod_shortage(did_ number) return number is
  cnt number;
begin
  for dd in (select * from doc where id=did_) loop
    select count(*) into cnt from command_order where state=2 and order_number=did_ and date_time_create between dd.date_order-1 and  dd.date_order+5;
    if cnt>0 then
       return 1;
    end if;
  end loop;
  return 0;
end;


end obj_cmd_order;
/
