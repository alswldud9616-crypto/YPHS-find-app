begin;
-- Trusted school operator only, with a service credential. Never called by a
-- web route. Used for the first identities and recovery after annual expiry.
create function public.yg_operator_bootstrap(p_name text,p_number text,p_hash text,p_year integer,p_role text,p_head boolean default false,p_user uuid default null) returns uuid language plpgsql set search_path=public as $$declare a uuid;begin
 if p_role not in ('SUPER_ADMIN','PRESIDENT_TEAM','WELFARE_MANAGER') or (p_head and p_role<>'WELFARE_MANAGER') or p_number !~ '^[0-9]{5}$' or char_length(trim(p_name)) not between 2 and 40 or p_hash not like 'scrypt$%' then raise exception '초기 관리자 정보를 확인해주세요.';end if;
 if yg_year() is null then insert into school_years values(p_year,make_date(p_year,3,1),make_date(p_year+1,3,1)-1,true);end if;
 if yg_year()<>p_year then raise exception '현재 학년도와 일치해야 해요.';end if;
 if p_user is null then insert into users(display_name) values(trim(p_name)) returning id into a;
 else a:=p_user;if not exists(select 1 from users where id=a and display_name=trim(p_name)) then raise exception '기존 계정을 확인해주세요.';end if;end if;
 insert into pin_credentials values(a,p_hash) on conflict(user_id) do update set pin_hash=excluded.pin_hash;
 delete from app_sessions where user_id=a;
 update student_verifications set status='EXPIRED' where user_id=a and school_year=p_year and status in ('ACCOUNT_PENDING','VERIFIED');
 update verification_uploads set delete_status='DELETION_PENDING' where verification_id in(select id from student_verifications where user_id=a) and delete_status<>'DELETED';
 insert into student_verifications(user_id,school_year,student_number,status,verified_at,reviewed_by,feedback) values(a,p_year,p_number,'VERIFIED',now(),a,'학교 운영 담당자의 초기 신원 확인');
 update council_roles set revoked_at=now() where user_id=a and school_year=p_year and revoked_at is null;
 insert into council_roles(user_id,school_year,role,is_head,can_deliver,starts_at,ends_at,granted_by) values(a,p_year,p_role::app_role,p_head,p_role<>'SUPER_ADMIN',now(),make_date(p_year+1,3,1)::timestamp at time zone 'Asia/Seoul',a);
 perform yg_log(a,'운영 담당자 초기 관리자 설정',a);return a;
end$$;
revoke all on function public.yg_operator_bootstrap(text,text,text,integer,text,boolean,uuid) from public,anon,authenticated;
grant execute on function public.yg_operator_bootstrap(text,text,text,integer,text,boolean,uuid) to service_role;
commit;
