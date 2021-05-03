create or replace trigger container_ad_e
after delete
ON container
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare 
 cnt number; 
BEGIN
 select count(*) into cnt from container_content 
 where container_id=:old.id and nvl(quantity,0)<>0;
 if :old.location<>0 then
   raise_application_error (-20003, 'It''s not allowed to delete container in ASK!');      
 end if;
 if cnt<>0 then
   raise_application_error (-20003, 'It''s not allowed to delete container with not epmty content!');      
 else
   delete from container_content where container_id=:old.id ;
 end if;
END;
/
