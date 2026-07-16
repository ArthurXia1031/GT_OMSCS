with base as (
    select
        concat(a.tran_acct_key,'_',a.tran_trsfr_acct_seq_nbr) as acct_id,
        a.fraud_tran_ind, a.tran_amt,
        iff(a.aprv_dcln_cde = 'A', true, false) as is_approved,
        a.hct_term_owner_name as merch_name,
        a.hct_term_owner_id   as mid,
        a.hct_mer_mcc         as mcc,          -- 你现在用的这列跑通了,保持
        array_construct_compact(
            /* ←—— 你 CPP 的 8 个 source case,原样 ——→ */
        ) as srcs
    from  a
    where a.tran_amt > 20
      and a.auth_dt between current_date()-15 and current_date()-1
),
hit as ( select * from base where array_size(srcs) > 0 ),
exploded as (
    select h.*, s.value::string as srce
    from hit h, lateral flatten(input => h.srcs) s
),
merch_src as (
    select
        srce,
        max(merch_name)                                                        as merch_name,   -- ①名字取 max,吸收变体
        mid, mcc,
        count(*)                                                               as tot_tran,
        sum(iff(fraud_tran_ind = 1, 1, 0))                                     as fraud_tran,
        count(distinct acct_id)                                                as tot_acct,     -- ②全部账户(不再只 decline 侧)
        count(distinct iff(fraud_tran_ind = 1, acct_id, null))                 as fraud_acct,
        count(distinct iff(fraud_tran_ind = 1 and is_approved,     acct_id, null)) as fraud_acct_apr,
        count(distinct iff(fraud_tran_ind = 1 and not is_approved, acct_id, null)) as fraud_acct_dcl,
        sum(iff(fraud_tran_ind = 1,                    tran_amt, 0))           as fraud_dlr,    -- ②总额 = apr + dcl
        sum(iff(fraud_tran_ind = 1 and is_approved,     tran_amt, 0))          as fraud_dlr_apr,
        sum(iff(fraud_tran_ind = 1 and not is_approved, tran_amt, 0))          as fraud_dlr_dcl
    from exploded
    group by srce, mid, mcc                                                    -- ①按 mid+mcc 分组,WALMART 变体合并
    qualify row_number() over (partition by srce order by fraud_dlr desc) <= 10 -- ③排名键 = 总额
),
merch_all as (
    select
        'All' as srce,
        max(merch_name)                                                        as merch_name,
        mid, mcc,
        count(*)                                                               as tot_tran,
        sum(iff(fraud_tran_ind = 1, 1, 0))                                     as fraud_tran,
        count(distinct acct_id)                                                as tot_acct,
        count(distinct iff(fraud_tran_ind = 1, acct_id, null))                 as fraud_acct,
        count(distinct iff(fraud_tran_ind = 1 and is_approved,     acct_id, null)) as fraud_acct_apr,
        count(distinct iff(fraud_tran_ind = 1 and not is_approved, acct_id, null)) as fraud_acct_dcl,
        sum(iff(fraud_tran_ind = 1,                    tran_amt, 0))           as fraud_dlr,
        sum(iff(fraud_tran_ind = 1 and is_approved,     tran_amt, 0))          as fraud_dlr_apr,
        sum(iff(fraud_tran_ind = 1 and not is_approved, tran_amt, 0))          as fraud_dlr_dcl
    from hit
    group by mid, mcc
    qualify row_number() over (order by fraud_dlr desc) <= 30
)
select * from merch_all
union all
select * from merch_src
order by srce, fraud_dlr desc;

--------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------

, sum(case when fraud_tran_ind = 1 then tran_amt else 0 end) as acct_fraud_dlr
, sum(case when fraud_tran_ind = 1 and hs = 'Y' then tran_amt else 0 end) as acct_fraud_dlr_hs
, sum(case when fraud_tran_ind = 1
           and datediff(minute, auth_tms, v_a_trx_lastverified_tms) >= 0
           and datediff(minute, auth_tms, v_a_trx_lastverified_tms) <= 15
      then tran_amt else 0 end) as acct_fraud_dlr_v15



, sum(case when f.acct_fraud = 1 and date(f.fraud_stat_dt) >= a.as_of then 0
           when f.acct_fraud = 1 then f.acct_fraud_dlr_hs
           else 0 end) as fraud_dlr_hs


, sum(case when c.acct_fraud = 1 and date(c.fraud_stat_dt) >= a.as_of then 0
           when c.acct_fraud = 1 then c.acct_fraud_dlr_v15
           else 0 end) as fraud_dlr_v15


-- All 行的 select 加:
,coalesce(fraud_dlr_hs, 0)  as FRAUD_DLR_HS
,cast(null as number)       as FRAUD_DLR_V15

-- tier 行的 select 加:
,cast(null as number)       as FRAUD_DLR_HS
,coalesce(fraud_dlr_v15, 0) as FRAUD_DLR_V15
