create or replace package obj_cmd_gas is -- объект команд перемещения контейнеров

  cmd_priority_container_accept number:= -9999999; -- приоритет команды при приеме контейнера на хранение - самый низкий

  -- public - для вызова извне
  procedure Form_Commands; -- основная процедура - формирование команд
  procedure crash_test_cmd_Gas_tact(rp_id_ number); -- такт общего крэш-теста
  procedure crash_test_cmd_accept(cell_name_ varchar2, rp_id_ number); -- крэш-тест приемки товара


  -- технические, чтоб можно было вызвать в SQL запросе
  function Get_Acc_Cell_Src_npp_RP(rp_src_npp_ number, rp_src_id_ number, rp_dest_id_ number) return number;  -- взять трек ячейки источника для приема контейнера (может не совпадать для разных складов)
  function get_always_out_bcg(cg_id in number, gd_id_ in varchar2, gd_party_id_ number) return number; -- считает, сколько уже подвезено товара по command_gas
  function get_cg_was_cnt_planned(cg_id_ number) return number; -- сколько штук запланировано к подвозу?
  function get_container_last_rp(container_barcode_ varchar2) return number;  -- получить ID огурца, на котором указанный контейнер хранился в последний раз 
  function get_last_side_zone(rp_id_ in number, side_ number) return number; -- взять последний вариант зоны для команды
  function get_quantity_accordance(delta in number,rpmode in number,q_cont in number) return number; -- считает параметр для сортировки команд отбора


  procedure prav_cg_status(rp_id_ number);  -- исправить статус команд, если нужно
  function presence_in_side(cg_id in number, cmd_side in number) return number; -- высчитать сторону предпочтительную для забора товара

  function presence_in_side_accurance(rp_id number, rp_max_npp number, cg_id number,cmd_side number,
         rpmode number,q_need number, gd_id varchar2) return number; -- =0 если есть на нужной стороне, 1 - нет

  -- получить ячейку для хранения контейнера
  function get_cell_name_for_accept(rp_id_ in number, cnt_id_  in number,  cg_type_id_ number,
       cg_cell_sname_ varchar2, cg_rp_id_ number, new_rp_id_ out number) return varchar2;

  -- есть ли незанятые командами ячейки для сброса
  function is_cg_otbor_cell_out_unlock(cg_id_ number) return number; 


  procedure parse_cg_cc(cg_id in number, ccont in varchar2, cmgd in number); -- парсит строку товара в таблицу




  


end obj_cmd_gas;
/
