CREATE OR REPLACE TRIGGER robot_bu_crp_e
BEFORE update of command_rp_id
ON robot
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnt number;
 -- cirec command_inner%rowtype;
 -- crprec command_rp%rowtype;
BEGIN
 if nvl(:old.command_rp_id,0)<>nvl(:new.command_rp_id,0) then -- назначена новая команда
   service.log2file('  триггер robot_bu_ciaid_e - сменили команду rp='||nvl(:old.command_rp_id,0)||' на '||nvl(:new.command_rp_id,0) ||' на робота '||:new.id);
 end if;
END;
/
