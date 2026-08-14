-- CNC MSP FORGE | SHOP-02 v1.0.0 | Quote status constraint fix 14/08/2026
-- The msp_quote price_status check predates the free qualification rule and
-- rejected free_qualifying rows; caught by the shop journey test before any
-- client hit it.

alter table msp_quote drop constraint msp_quote_price_status_check;
alter table msp_quote add constraint msp_quote_price_status_check
  check (price_status in ('indicative', 'firm', 'free_qualifying'));
