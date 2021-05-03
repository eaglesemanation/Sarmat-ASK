create or replace package obj_cmd_order is -- объект команд сервера заказов 

  -- public - для вызова извне
  procedure Form_Commands;

  -- get
  function get_Order_Content_Out_Picked(cmd_order_id_ number, deficite_type_ number default 0) return number; -- сколько по cmd_order уже отоьрано оператором
  function get_Order_Content_Out_Promis(cmd_order_id_ number) return number;
  function get_container_izlish(cnt_id_ in number, gd_id_ in varchar2, gd_party_id_ number) return number;
  function get_ras_gd_rest(doc_id_ number, gd_id_ number, party_id_ number) return number;
  function get_rasdoc_rest(doc_id_ number) return number;
  function is_rashod_shortage(did_ number) return number;


  procedure Order_Content_Out_Doz_on_dfct;

  -- сервисные ф-ии

  -- отменяет ошибочно данную команду
  procedure Cancel_Error_Cmd_Cont_Out(cmd_order_id_ number);
 
                                        
end obj_cmd_order;
/
