-- sessions must account for every event: returns a row only if the totals differ
select s.n_in_sessions, e.n_events
from (select sum(n_events) as n_in_sessions from {{ ref('fct_sessions') }}) s
cross join (select count(*) as n_events from {{ ref('stg_web_events') }}) e
where s.n_in_sessions <> e.n_events
