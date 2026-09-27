begin;
create function public.yg_state(p_actor uuid,p_year integer default null) returns jsonb language plpgsql set search_path=public as $$
declare y integer:=yg_year();yr integer;v boolean:=yg_verified(p_actor);m boolean:=yg_manager(p_actor);result jsonb;
begin
 yr:=coalesce(p_year,y);if yr<>y and not m then raise exception '이전 학년도 조회 권한이 없어요.';end if;
 result:=jsonb_build_object('year',y,'role',yg_role(p_actor),'verified',v,'canVerify',yg_verifier(p_actor),'canDeliver',yg_deliverer(p_actor),'years',coalesce((select jsonb_agg(year order by year desc) from school_years where year=y or m),'[]'::jsonb),'user',(select jsonb_build_object('id',u.id,'name',u.display_name,'number',coalesce((select student_number from student_verifications where user_id=u.id order by school_year desc,created_at desc limit 1),''),'verification',coalesce((select status from student_verifications where user_id=u.id and school_year=y order by created_at desc limit 1),'REVERIFY')) from users u where u.id=p_actor));
 if not v then return result;end if;
 result:=result||jsonb_build_object(
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.name,'category',k.name,'place',i.found_location,'detail',i.place_detail,'date',i.found_date,'color',i.color,'brand',i.brand,'description',i.public_description,'status',i.status,'year',i.current_year,'originYear',i.origin_year,'approvedAt',i.approved_at,'longOverdue',i.approved_at<=now()-interval '14 days' and i.status in ('STORED','CLAIM_PENDING'),'photo','/api/image?kind=item&id='||i.id,'storage','본관 중앙 현관 분실물함') order by i.approved_at desc) from items i join categories k on k.id=i.category_id where i.current_year=yr or (m and (i.origin_year=yr or exists(select 1 from year_transfers t where t.item_id=i.id and t.from_year=yr)))),'[]'::jsonb),
 'submissions',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'category',k.name,'place',r.found_location,'detail',r.place_detail,'date',r.found_date,'description',r.public_description,'status',r.status,'resolution',r.resolution,'feedback',r.feedback,'photo','/api/image?kind=submission&id='||r.id,'student',u.display_name,'mine',r.submitter_id=p_actor) order by r.created_at desc) from item_submission_requests r join categories k on k.id=r.category_id join users u on u.id=r.submitter_id where r.school_year=yr and (r.submitter_id=p_actor or m)),'[]'::jsonb),
 'claims',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'itemId',c.item_id,'name',i.name,'student',u.display_name,'answer',c.private_answer,'status',c.status,'feedback',c.feedback,'codeEncrypted',case when c.claimant_id=p_actor then c.pickup_code_ciphertext end,'mine',c.claimant_id=p_actor,'reservation',(select jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join users d on d.id=s.staff_id where r.claim_id=c.id and r.status='RESERVED'),'history',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status) order by r.created_at desc) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join users d on d.id=s.staff_id where r.claim_id=c.id),'[]'::jsonb)) order by c.created_at desc) from claim_requests c join items i on i.id=c.item_id join users u on u.id=c.claimant_id where c.school_year=yr and (c.claimant_id=p_actor or m)),'[]'::jsonb),
 'slots',coalesce((select jsonb_agg(t.starts_at order by t.starts_at) from (select distinct s.starts_at from pickup_slots s join staff_availability a on a.id=s.availability_id where s.school_year=y and a.cancelled_at is null and s.starts_at>now() and yg_deliverer(s.staff_id) and not exists(select 1 from pickup_schedules r where r.slot_id=s.id and r.status in ('RESERVED','COMPLETED'))) t),'[]'::jsonb),
 'availability',coalesce((select jsonb_agg(jsonb_build_object('id',id,'starts',starts_at,'ends',ends_at) order by starts_at) from staff_availability where staff_id=p_actor and school_year=y and ends_at>now() and cancelled_at is null and yg_deliverer(p_actor)),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'starts',s.starts_at,'ends',s.ends_at,'place',r.pickup_place,'staff',d.display_name,'status',r.status,'name',i.name,'photo','/api/image?kind=assigned&id='||r.id,'storageNumber',pr.storage_number,'student',u.display_name,'studentNumber',(select student_number from student_verifications where user_id=u.id and school_year=y and status='VERIFIED' limit 1),'codeEncrypted',c.pickup_code_ciphertext) order by s.starts_at) from pickup_schedules r join pickup_slots s on s.id=r.slot_id join claim_requests c on c.id=r.claim_id join items i on i.id=c.item_id join item_private_details pr on pr.item_id=i.id join users u on u.id=c.claimant_id join users d on d.id=s.staff_id where s.staff_id=p_actor and s.school_year=y and r.status='RESERVED' and yg_deliverer(p_actor)),'[]'::jsonb),
 'verifications',coalesce((select jsonb_agg(jsonb_build_object('id',sv.id,'name',u.display_name,'number',sv.student_number,'status',sv.status,'created',sv.created_at,'deletion',(select delete_status from verification_uploads where verification_id=sv.id order by expires_at desc limit 1)) order by sv.created_at) from student_verifications sv join users u on u.id=sv.user_id where sv.school_year=y and yg_verifier(p_actor) and (sv.status='ACCOUNT_PENDING' or exists(select 1 from verification_uploads where verification_id=sv.id and delete_status='DELETION_PENDING'))),'[]'::jsonb),
 'members',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'name',u.display_name,'number',sv.student_number,'role',yg_role(u.id),'head',coalesce(cr.is_head,false),'deliver',coalesce(cr.can_deliver,false))) from users u join student_verifications sv on sv.user_id=u.id and sv.school_year=y and sv.status='VERIFIED' left join council_roles cr on cr.user_id=u.id and cr.school_year=y and cr.revoked_at is null where yg_role(p_actor)='SUPER_ADMIN'),'[]'::jsonb),
 'audit',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'text',u.display_name||' · '||l.action,'created',l.created_at) order by l.created_at desc) from audit_logs l join users u on u.id=l.actor_id where l.school_year=yr and m),'[]'::jsonb));
 return result;
end$$;
create function public.yg_image(p_actor uuid,p_kind text,p_id uuid) returns jsonb language plpgsql set search_path=public as $$declare path text;begin
 if p_kind='verification' then
  if not yg_verifier(p_actor) then raise exception '학생증 열람 권한이 없어요.';end if;
  select vu.object_path into path from verification_uploads vu join student_verifications sv on sv.id=vu.verification_id where sv.id=p_id and sv.school_year=yg_year() and sv.status='ACCOUNT_PENDING' and vu.delete_status='PENDING' and vu.expires_at>now();
  if path is not null then perform yg_log(p_actor,'학생증 열람',p_id);end if;
  return jsonb_build_object('bucket','student-verifications','path',path);
 end if;
 if not yg_verified(p_actor) then raise exception '재학생 인증이 필요해요.';end if;
 if p_kind='item' then
  select im.object_path into path from item_images im join items i on i.id=im.item_id where i.id=p_id and im.is_approved_public and (i.current_year=yg_year() or yg_manager(p_actor)) limit 1;
 elsif p_kind='submission' then
  select photo_path into path from item_submission_requests where id=p_id and (submitter_id=p_actor or yg_manager(p_actor));
 elsif p_kind='assigned' then
  select im.object_path into path from pickup_schedules r join pickup_slots s on s.id=r.slot_id join claim_requests c on c.id=r.claim_id join item_images im on im.item_id=c.item_id where r.id=p_id and r.status='RESERVED' and s.staff_id=p_actor and yg_deliverer(p_actor) limit 1;
 end if;
 return jsonb_build_object('bucket','item-photos','path',path);end$$;
create function public.yg_maintenance() returns void language plpgsql set search_path=public as $$declare r record;begin
 for r in select sv.* from student_verifications sv where sv.status='ACCOUNT_PENDING' and exists(select 1 from verification_uploads u where u.verification_id=sv.id and u.expires_at<=now() and u.delete_status<>'DELETED') for update loop
  update student_verifications set status='REJECTED',feedback='인증 사진 보관기간이 만료됐어요. 다시 제출해주세요.' where id=r.id;
  perform yg_notify(r.user_id,'ACCOUNT_REJECTED','인증 사진이 만료됐어요. 다시 제출해주세요.',r.id);
 end loop;
 update verification_uploads set delete_status='DELETION_PENDING' where delete_status='PENDING' and expires_at<=now();
 for r in select p.id,c.claimant_id from pickup_schedules p join pickup_slots s on s.id=p.slot_id join claim_requests c on c.id=p.claim_id where p.status='RESERVED' and p.reminded_at is null and s.starts_at>now() and s.starts_at<=now()+interval '30 minutes' for update of p skip locked loop
  perform yg_notify(r.claimant_id,'PICKUP_REMINDER','수령 예약 시간이 가까워졌어요.',r.id);
  update pickup_schedules set reminded_at=now() where id=r.id;
 end loop;
 delete from app_sessions where expires_at<now();
 delete from login_limits where window_start<now()-interval '1 day';
end$$;
revoke all on function public.yg_state(uuid,integer),public.yg_image(uuid,text,uuid),public.yg_maintenance() from public,anon,authenticated;
grant execute on function public.yg_state(uuid,integer),public.yg_image(uuid,text,uuid),public.yg_maintenance() to service_role;
commit;
