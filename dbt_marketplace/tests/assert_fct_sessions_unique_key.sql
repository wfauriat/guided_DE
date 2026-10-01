-- (user_id, session_no) is the grain of fct_sessions; returns any key that appears more than once
select user_id, session_no, count(*) as n
from {{ ref('fct_sessions') }}
group by user_id, session_no
having count(*) > 1
