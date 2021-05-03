CREATE OR REPLACE TRIGGER rp_bu_middle_e
BEFORE update of middle_npp
ON repository_part
REFERENCING NEW AS NEW OLD AS OLD
FOR EACH ROW
declare
 cnpp number;
 cside number;
 cnt_assigned number;
BEGIN
  if nvl(:new.middle_npp,0)<>nvl(:old.middle_npp,0) then
     cnpp:=:new.middle_npp;
     cside:=0;
     cnt_assigned:=0;
     loop
       exit when cnt_assigned>:new.max_npp+1;
       if cnt_assigned>(:new.max_npp+1)/2 then
         cside:=1;
       end if;
       update track set side=cside 
       where repository_part_id=:new.id and npp=cnpp;
       cnt_assigned:=cnt_assigned+1;
       if cnpp>=:new.max_npp then
         cnpp:=0;
       else
         cnpp:=cnpp+1;
       end if;
     end loop;
     for tt in (select * from track where repository_part_id=:new.id) loop
       if :new.middle_npp>tt.npp then
         if :new.middle_npp-tt.npp>1+tt.npp+(:new.max_npp-:new.middle_npp) then
           update track set distance_from_middle = 1+tt.npp+(:new.max_npp-:new.middle_npp)
           where id=tt.id;
         else 
           update track set distance_from_middle = :new.middle_npp-tt.npp
           where id=tt.id;
         end if;
       else
         if tt.npp-:new.middle_npp>1+:new.max_npp-tt.npp+:new.middle_npp then
           update track set distance_from_middle = 1+:new.max_npp-tt.npp+:new.middle_npp
           where id=tt.id;
         else
           update track set distance_from_middle = tt.npp-:new.middle_npp
           where id=tt.id;
         end if;
       end if;
     end loop;
  end if;
 
END;
/
