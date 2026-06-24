with
-- 报告日历:B-对齐,顶到 cd-1
asof as (
    select distinct batch_dt as as_of                                -- ★ distinct 加回
    from   "SFAAP"."WS_CARD_FRAUD_DATA".mliu_check_udv
    where  batch_dt between current_date()-54 and current_date()-1
),

-- 分母:base 已是 账户×批日 粒度,按 11 天窗 distinct
base_agg as (
    select b.UDVsrce as source, a.as_of as auth_dt,
           count(distinct b.acct_nbr) as tot_acct
    from   asof a
    join  mliu_check_udv b
           on b.batch_dt between a.as_of-10 and a.as_of               -- ★ -10
    group by b.UDVsrce, a.as_of
),

-- All 的 followup 聚合(同 11 天窗,distinct 重算)
flwup_agg as (
    select f.UDVsrce as source, a.as_of as auth_dt,
           count(distinct case when f.acct_fraud=1
                 then f.tran_acct_key||'_'||f.tran_trsfr_acct_seq_nbr end) as fraud_acct,
           sum(case when f.acct_fraud=1 then f.acct_fraud_dlr else 0 end)  as fraud_dlr
    from   asof a
    join   mliu_udvlvl_flwup_acct f
           on f.batch_dt between a.as_of-10 and a.as_of               -- ★ -10
    group by f.UDVsrce, a.as_of
),

-- All 行 = 分母 + followup
all_rows as (
    select b.source, 'All' as tier_info, b.auth_dt, b.tot_acct,
           coalesce(g.fraud_acct, 0) as fraud_acct,
           coalesce(g.fraud_dlr , 0) as fraud_dlr
    from   base_agg b
    left join flwup_agg g
           on g.source = b.source and g.auth_dt = b.auth_dt
),

-- Tier 行:approved fraud;tot_acct 留空(分母只在 All)
tier_rows as (
    select c.UDVsrce as source, c.Tier_info as tier_info, a.as_of as auth_dt,
           cast(null as number) as tot_acct,
           count(distinct case when c.acct_fraud=1
                 then c.tran_acct_key||'_'||c.tran_trsfr_acct_seq_nbr end) as fraud_acct,
           sum(case when c.acct_fraud=1 then c.acct_fraud_dlr else 0 end)  as fraud_dlr
    from   asof a
    join   mliu_udvlvl_aprv_flwup_acct c
           on c.batch_dt between a.as_of-10 and a.as_of               -- ★ -10
    group by c.UDVsrce, c.Tier_info, a.as_of
)

select source, tier_info, auth_dt, tot_acct, fraud_acct, fraud_dlr from all_rows
union all
select source, tier_info, auth_dt, tot_acct, fraud_acct, fraud_dlr from tier_rows
order by source, auth_dt, tier_info;
