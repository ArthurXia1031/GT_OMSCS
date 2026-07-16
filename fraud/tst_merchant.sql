with base as (
    select
        concat(a.tran_acct_key,'_',a.tran_trsfr_acct_seq_nbr) as acct_id,
        a.fraud_tran_ind, a.tran_amt,
        iff(a.aprv_dcln_cde = 'A', true, false) as is_approved,
        a.hct_term_owner_name as merch_name,
        a.hct_term_owner_id   as mid,
        a.hct_mer_mcc         as mcc,
        -- Testing 归因:交易行自带各测试的事件日期列;auth 落在 [事件日, 事件日+10] 即命中该 source。
        -- ⚠ 名字必须和 Q2 过程 SQL 的 UDVsrce 字符串一字不差,§02.1 By-Process 才能和 process 对上。
        array_construct_compact(
            case when cast(a.auth_dt as date) between cast(a.v_a_test_big_merch_dt as date)        and cast(a.v_a_test_big_merch_dt as date)+10        then 'v_a_test_big_merch_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_d_low_dlr_frd_merch_dt as date)     and cast(a.v_d_low_dlr_frd_merch_dt as date)+10     then 'v_d_low_dlr_frd_merch_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_a_high_prefrd_merch_test_dt as date) and cast(a.v_a_high_prefrd_merch_test_dt as date)+10 then 'v_a_high_prefrd_merch_test_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_a_no_hist_email_test_dt as date)    and cast(a.v_a_no_hist_email_test_dt as date)+10    then 'v_a_no_hist_email_test_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_d_0dlr_highscr_tran_dt as date)     and cast(a.v_d_0dlr_highscr_tran_dt as date)+10     then 'v_d_0dlr_highscr_tran_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_a_testing_u_mrch_risky_dt as date)  and cast(a.v_a_testing_u_mrch_risky_dt as date)+10  then 'v_a_testing_u_mrch_risky_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_a_testing_0_cnp_risky_dt as date)   and cast(a.v_a_testing_0_cnp_risky_dt as date)+10   then 'v_a_testing_0_cnp_risky_dt' end,
            case when cast(a.auth_dt as date) between cast(a.v_a_1dlr_highscr_exp_date as date)    and cast(a.v_a_1dlr_highscr_exp_date as date)+10    then 'v_a_1dlr_highscr_exp_date' end
            /* ↑ 这 8 个是我从你截图里读到的;你的 Q2 有 15 个 testing source —
               照 mliu_udvlvl_flwup_acct 的 branch 清单 1:1 补齐剩下的,一 branch 一行 case */
        ) as srcs
    from  a
    where a.tran_amt > 20
      and a.auth_dt between current_date()-10 and current_date()-1     -- Testing 快照窗 = 10d(与 Q2 一致)
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
