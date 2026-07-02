    sum(case when e.fraud_tran_ind = 1 and date(e.fraud_stat_dt) > a.as_of then 0
             when e.fraud_tran_ind = 1 and e.is_hs then e.tran_amt
             else 0 end)                                                    as fraud_dlr_hs,
    sum(case when e.fraud_tran_ind = 1 and date(e.fraud_stat_dt) > a.as_of then 0
             when e.fraud_tran_ind = 1 and e.is_v15 then e.tran_amt
             else 0 end)                                                    as fraud_dlr_v15,
