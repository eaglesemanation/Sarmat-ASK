CREATE OR REPLACE TRIGGER command_gas_oc_bi_e
BEFORE INSERT
ON command_gas_out_container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 qnt number;
 qnt_early number;
 qnt_need number;
 cnt number;
BEGIN
 -- добавился новый контейнер по подвозу контейнеров - распределяем его
 -- qnt:=:new.quantity;
 select quantity_to_pick into qnt 
 from command_gas_out_container_plan 
 where cmd_gas_id =:new.cmd_gas_id and container_id =:new.container_id ;
 service.log2file('cooc: привезли контейнер '||:new.container_id||' со штрих-кодом '||:new.container_barcode||
                  ' с товаром ='||:new.good_desc_id || ' с партией '||:new.gd_party_id||' кол-во='||:new.quantity||
                  ' в ячейку '||:new.cell_name );
 select count(*) into cnt from container_collection
 where state=0 and container_id=:new.container_id; -- and cmd_gas_id=:new.cmd_gas_id;
 if cnt<>0 then
   --raise_application_error (-20003, 'Container collection on container '||:new.container_id||' already opened!', TRUE);
   null;
 else
   service.log2file('cooc: добавляем  container_collection с  :new.cmd_gas_id = '||:new.cmd_gas_id);
   -- начинаем отбор - открываем его
   insert into container_collection (cell_name, container_id, cmd_gas_id , container_barcode )
   values(:new.cell_name ,:new.container_id, :new.cmd_gas_id, :new.container_barcode );
 end if;
 -- пробегаем и распределяем
 for co in (select * from command_order where command_gas_id=:new.cmd_gas_id
             and state in (1,3) and command_type_id=15
             order by priority desc, group_number, QUANTITY_FROM_GAS) loop
    service.log2file('  cooc: есть куда распределить co.id='||co.id);
    -- считаем, сколько надо еще подвезти
    select nvl(sum(quantity),0) into qnt_early 
    from command_order_out_container cooc
    where cooc.cmd_order_id =co.id;
    service.log2file('  cooc: ранее было собрано '||qnt_early);
    qnt_need:=co.quantity_promis-qnt_early;
    service.log2file('  cooc: надо добрать '||qnt_need);
    if qnt_need=0 then
      -- странная ситуация - не в статусе 5, а все покрыто
      service.log2file('  cooc: !!! странная ситуация - не в статусе 5, а все покрыто');
      update command_order set state=5 where id=co.id;
    else
      if qnt>=qnt_need then -- хватает покрыть весь запрос
        service.log2file('  cooc: хватает покрыть весь запас: надо '||qnt_need||
                         ' а есть '||qnt);
        insert into command_order_out_container (cmd_order_id, container_id, container_barcode,
          good_desc_id, quantity, order_number, group_number,
          cell_name, point_number, command_gas_id, gd_party_id)
        values (co.id,:new.container_id, :new.container_barcode,
          :new.good_desc_id, qnt_need, co.order_number, co.group_number,
          :new.cell_name ,co.point_number, :new.cmd_gas_id , :new.gd_party_id);
        service.log2file('  cooc: добавили в command_order_out_container');
        qnt:=qnt-qnt_need;
        update command_order set state=5 where id=co.id;
        service.log2file('  cooc: поменяли статус command_order в 5 id='||co.id);
        update command_gas_out_container_plan set quantity_was_picked =quantity_was_picked +qnt_need
        where cmd_gas_id =:new.cmd_gas_id and container_id =:new.container_id ;
      else
      -- покрываем часть запроса
        service.log2file('  cooc: можно покрыть лишь часть: надо '||qnt_need||
                         ' а есть '||qnt);
        insert into command_order_out_container (cmd_order_id, container_id, container_barcode,
          good_desc_id, quantity, order_number, group_number,
          cell_name, point_number, command_gas_id, gd_party_id)
        values (co.id,:new.container_id, :new.container_barcode,
          :new.good_desc_id, qnt, co.order_number, co.group_number,
          :new.cell_name ,co.point_number, :new.cmd_gas_id , :new.gd_party_id);
        update command_order set state=3 where id=co.id and state=1;
        service.log2file('  cooc: поменяли статус command_order в 3 id='||co.id);
        update command_gas_out_container_plan set quantity_was_picked =quantity_was_picked +qnt
        where cmd_gas_id =:new.cmd_gas_id and container_id =:new.container_id ;
        qnt:=0;
      end if;
    end if;
    exit when qnt=0;
 end loop;

END;
/
