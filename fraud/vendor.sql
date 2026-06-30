-- ============ VENDOR — 时间序列(B-对齐, 15 天窗), union 用 FLATTEN 收口 ============
with
-- (1) 一次扫描:把 8 个源列炸成 (source, batch_dt) —— 替代 mliu_vendor1..N + union
ven_raw as (
    select
        f.key                  as source,                 -- 源名(= object 的 key)
        cast(f.value as date)  as batch_dt,               -- 该源的批/曝光日(= 列值)
        t.tran_acct_key, t.tran_trsfr_acct_seq_nbr,
        case when t.cnp_tier in ('1','A') then 'T1'
             when t.cnp_tier in ('2','B') then 'T2'
             when t.cnp_tier in ('3')     then 'T3' end as tier_info,
        t.fraud_tran_ind, t.tran_amt, t.aprv_dcln_cde
    from base t,
    lateral flatten(input => object_construct(            -- ★ NULL 值自动丢弃 → 只留命中的源
        'xxxx',        t.xxxx,
    )) f
    where cast(t.auth_dt as date) between cast(f.value as date) and cast(f.value as date)+15  -- 成熟窗
      and cast(f.value as date) >= current_date()-69     -- 回看(asof 最早-54, 再减 15 窗)
      and t.tran_amt > 20
),

-- (2) 账户级 · All(不带 approve;一账户一批日一行)
ven_all_acct as (
    select source, batch_dt, tran_acct_key, tran_trsfr_acct_seq_nbr,
           max(fraud_tran_ind)                                       as acct_fraud,
           sum(case when fraud_tran_ind=1 then tran_amt else 0 end)  as acct_fraud_dlr
    from ven_raw
    group by 1,2,3,4
),

-- (3) 账户级 · Tier(approved 过滤,带 tier)
ven_tier_acct as (
    select source, tier_info, batch_dt, tran_acct_key, tran_trsfr_acct_seq_nbr,
           max(fraud_tran_ind)                                       as acct_fraud,
           sum(case when fraud_tran_ind=1 then tran_amt else 0 end)  as acct_fraud_dlr
    from ven_raw
    where aprv_dcln_cde='A'
    group by 1,2,3,4,5
),

-- (4) 报告日历(B-对齐, 顶到 cd-1)
asof as (
    select distinct batch_dt as as_of
    from   ven_raw
    where  batch_dt between current_date()-54 and current_date()-1
),

-- (5) All 行:分母/分子都在 followup 窗内 distinct 重算(15 天窗)
all_rows as (
    select v.source as source, 'All' as tier_info, a.as_of as auth_dt,
           count(distinct v.tran_acct_key||'_'||v.tran_trsfr_acct_seq_nbr) as tot_acct,
           count(distinct case when v.acct_fraud=1
                 then v.tran_acct_key||'_'||v.tran_trsfr_acct_seq_nbr end) as fraud_acct,
           sum(case when v.acct_fraud=1 then v.acct_fraud_dlr else 0 end)  as fraud_dlr
    from   asof a
    join   ven_all_acct v on v.batch_dt between a.as_of-15 and a.as_of     -- ★ 15 天窗
    group by v.source, a.as_of
),

-- (6) Tier 行:approved followup 内的 distinct 账户当分母(tier AFPR 用它)
tier_rows as (
    select v.source as source, v.tier_info as tier_info, a.as_of as auth_dt,
           count(distinct v.tran_acct_key||'_'||v.tran_trsfr_acct_seq_nbr) as tot_acct,
           count(distinct case when v.acct_fraud=1
                 then v.tran_acct_key||'_'||v.tran_trsfr_acct_seq_nbr end) as fraud_acct,
           sum(case when v.acct_fraud=1 then v.acct_fraud_dlr else 0 end)  as fraud_dlr
    from   asof a
    join   ven_tier_acct v on v.batch_dt between a.as_of-15 and a.as_of
    group by v.source, v.tier_info, a.as_of
)

select source, tier_info, auth_dt, tot_acct, fraud_acct, fraud_dlr from all_rows
union all
select source, tier_info, auth_dt, tot_acct, fraud_acct, fraud_dlr from tier_rows
order by source, auth_dt, tier_info;
