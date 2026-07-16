with base as (
    select
        concat(a.tran_acct_key,'_',a.tran_trsfr_acct_seq_nbr) as acct_id,
        a.fraud_tran_ind, a.tran_amt,
        iff(a.aprv_dcln_cde = 'A', true, false) as is_approved,
        a.hct_term_owner_name as merch_name,
        a.hct_term_owner_id   as mid,
        a.hct_mer_mcc         as mcc,
        -- Vendor 归因:与你 Q2 vendor SQL 的 srcs 数组保持一字不差(7 个 indicator + 1 个日期窗)
        array_construct_compact(
            case when a.v_a_gemini_35d_ind        = 1 then 'v_a_gemini_35d_ind'        end,
            case when a.v_a_gemini_35to90d_ind    = 1 then 'v_a_gemini_35to90d_ind'    end,
            case when a.v_a_gemini_90to270d_ind   = 1 then 'v_a_gemini_90to270d_ind'   end,
            case when a.v_a_gemini_10d_bihrly_ind = 1 then 'v_a_gemini_10d_bihrly_ind' end,
            case when a.v_a_gemini_exp_miss_ind   = 1 then 'v_a_gemini_exp_miss_ind'   end,
            case when a.v_a_q6_45d_ind            = 1 then 'v_a_q6_45d_ind'            end,
            case when a.v_a_q6_sameday_ind        = 1 then 'v_a_q6_sameday_ind'        end,
            case when cast(a.auth_dt as date) - cast(a.v_a_multisrce_dt as date) between 0 and 3
                 then 'Multisrce_3day_Ind' end
        ) as srcs
    from  a
    where a.tran_amt > 20
      and a.auth_dt between current_date()-15 and current_date()-1     -- Vendor 快照窗 = 15d(与 Q2 一致)
),
hit as ( select * from base where array_size(srcs) > 0 ),
exploded as (
    select h.*, s.value::string as srce
    from hit h, lateral flatten(input => h.srcs) s
),
merch_src as (
    select
        srce,
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
    from exploded
    group by srce, mid, mcc
    qualify row_number() over (partition by srce order by fraud_dlr desc) <= 10
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
