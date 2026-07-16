array_construct_compact(
    case when a.v_d_batchlist_lul_ind      = 1 then 'v_d_batchlist_lul_ind'      end,
    case when a.v_d_atm_seg1_long_ind      = 1 then 'v_d_atm_seg1_long_ind'      end,
    case when a.v_d_atm_seg2_ind           = 1 then 'v_d_atm_seg2_ind'           end,
    case when a.v_d_low_settle_test_ind    = 1 then 'v_d_low_settle_test_ind'    end,
    case when a.v_d_atm_seg1_ind           = 1 then 'v_d_atm_seg1_ind'           end,
    case when a.v_d_atm_risky_acct_exp_ind = 1 then 'v_d_atm_risky_acct_exp_ind' end,
    case when a.v_d_atm_risky_acct_ind     = 1 then 'v_d_atm_risky_acct_ind'     end,
    case when a.v_d_bad_mrch_test_ind      = 1 then 'v_d_bad_mrch_test_ind'      end,
    case when a.v_d_badexternal_ind        = 1 then 'v_d_badexternal_ind'        end
) as srcs
