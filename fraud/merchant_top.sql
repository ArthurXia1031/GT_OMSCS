with base as (
    select
        concat(a.tran_acct_key,'_',a.tran_trsfr_acct_seq_nbr) as acct_id,
        a.fraud_tran_ind, a.tran_amt,
        iff(a.aprv_dcln_cde = 'A', true, false) as is_approved,
        a.hct_term_owner_name as merch_name,
        a.hct_term_owner_id   as mid,
        a.mcc_cde             as mcc,
        array_construct_compact(
            /* ←—— 你 CPP Q2 里同一套 8 个 source 的 case ——→ */
        ) as srcs
    from  a
    where a.tran_amt > 20
      and a.auth_dt between current_date()-15 and current_date()-1   -- CPP/Vendor 15d;Testing 10d
),
hit as ( select * from base where array_size(srcs) > 0 ),
exploded as (
    select h.*, s.value::string as srce
    from hit h, lateral flatten(input => h.srcs) s
),
merch_src as (   -- merchant × source:归因粒度 → By Process 视图
    select
        srce, merch_name, mid, mcc,
        count(*)                                                                  as tot_tran,
        sum(iff(fraud_tran_ind=1,1,0))                                            as fraud_tran,
        count(distinct iff(not is_approved, acct_id, null))                       as tot_acct,
        count(distinct iff(fraud_tran_ind=1 and not is_approved, acct_id, null))  as fraud_acct,
        sum(iff(fraud_tran_ind=1 and is_approved, tran_amt, 0))                   as fraud_dlr
    from exploded
    group by 1,2,3,4
    qualify row_number() over (partition by srce order by fraud_dlr desc) <= 10   -- 每源 top-10
),
merch_all as (   -- merchant 去重总量:每笔交易只算一次 → By Total $ 排名
    select
        'All' as srce, merch_name, mid, mcc,
        count(*)                                                                  as tot_tran,
        sum(iff(fraud_tran_ind=1,1,0))                                            as fraud_tran,
        count(distinct iff(not is_approved, acct_id, null))                       as tot_acct,
        count(distinct iff(fraud_tran_ind=1 and not is_approved, acct_id, null))  as fraud_acct,
        sum(iff(fraud_tran_ind=1 and is_approved, tran_amt, 0))                   as fraud_dlr
    from hit
    group by 2,3,4
    qualify row_number() over (order by fraud_dlr desc) <= 30                     -- 总榜 top-30
)
select * from merch_all
union all
select * from merch_src
order by srce, fraud_dlr desc;


-- findstr /c:"injFam.merchants" cmpt_report_pro_vv.html
-- findstr /c:"\"merchants\"" cmpt_report_test_0713.html
