-- Run after schema.sql and replacement-adjustments.sql.
-- This migration supports replacements from both original sales and earlier
-- replacement items, and records any customer price difference atomically.

alter table public.sales
  add column if not exists sale_type text not null default 'sale',
  add column if not exists payment_method text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'sales_sale_type_check'
      and conrelid = 'public.sales'::regclass
  ) then
    alter table public.sales
      add constraint sales_sale_type_check
      check (sale_type in ('sale', 'replacement_charge'));
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'sales_payment_method_check'
      and conrelid = 'public.sales'::regclass
  ) then
    alter table public.sales
      add constraint sales_payment_method_check
      check (payment_method is null or payment_method in ('cash', 'gcash'));
  end if;
end;
$$;

alter table public.inventory_adjustments
  add column if not exists sale_id bigint references public.sales(id) on delete set null,
  add column if not exists source_adjustment_id bigint references public.inventory_adjustments(id) on delete set null,
  add column if not exists original_product_id bigint references public.products(id) on delete set null,
  add column if not exists original_product_name text,
  add column if not exists original_unit_price numeric(12, 2),
  add column if not exists replacement_unit_price numeric(12, 2),
  add column if not exists additional_amount numeric(12, 2) not null default 0,
  add column if not exists payment_method text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'inventory_adjustments_payment_method_check'
      and conrelid = 'public.inventory_adjustments'::regclass
  ) then
    alter table public.inventory_adjustments
      add constraint inventory_adjustments_payment_method_check
      check (payment_method is null or payment_method in ('cash', 'gcash'));
  end if;
end;
$$;

create index if not exists idx_inventory_adjustments_sale_id
  on public.inventory_adjustments(sale_id);
create index if not exists idx_inventory_adjustments_source_adjustment_id
  on public.inventory_adjustments(source_adjustment_id);

drop function if exists public.complete_replacement(bigint, bigint, integer, text);
drop function if exists public.complete_replacement(bigint, bigint, integer, text, text);
drop function if exists public.complete_replacement(text, bigint, bigint, integer, text, text);

create or replace function public.complete_replacement(
  p_source_type text,
  p_source_id bigint,
  p_replacement_product_id bigint,
  p_quantity integer,
  p_reason text,
  p_payment_method text default null
)
returns table (replacement_id bigint, additional_amount numeric)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_sale public.sales%rowtype;
  v_source_adjustment public.inventory_adjustments%rowtype;
  v_product public.products%rowtype;
  v_role text;
  v_employee_name text;
  v_already_replaced integer;
  v_remaining_quantity integer;
  v_original_unit_price numeric(12, 2);
  v_additional_amount numeric(12, 2);
  v_payment_method text;
  v_adjustment_id bigint;
  v_root_sale_id bigint;
  v_source_product_id bigint;
  v_source_product_name text;
  v_source_adjustment_id bigint;
begin
  if auth.uid() is null then
    raise exception 'You must be signed in to process a replacement.';
  end if;

  select role, display_name
    into v_role, v_employee_name
    from public.profiles
    where id = auth.uid();

  if v_role is distinct from 'employee' then
    raise exception 'Only an employee account can process replacements.';
  end if;

  if p_quantity is null or p_quantity < 1 then
    raise exception 'Replacement quantity must be at least one.';
  end if;

  if nullif(trim(p_reason), '') is null then
    raise exception 'A replacement reason is required.';
  end if;

  if p_source_type = 'sale' then
    select * into v_sale
      from public.sales
      where id = p_source_id and sale_type = 'sale'
      for update;

    if not found then
      raise exception 'The selected sold item could not be found.';
    end if;

    if v_sale.quantity < 1 then
      raise exception 'This sales row cannot be used as a sold item.';
    end if;

    select coalesce(sum(quantity), 0)::integer into v_already_replaced
      from public.inventory_adjustments
      where sale_id = p_source_id and source_adjustment_id is null;

    v_remaining_quantity := v_sale.quantity - v_already_replaced;
    v_root_sale_id := v_sale.id;
    v_source_product_id := v_sale.product_id;
    v_source_product_name := v_sale.product_name;
    v_original_unit_price := round(v_sale.total_amount / v_sale.quantity, 2);
    v_source_adjustment_id := null;
  elsif p_source_type = 'replacement' then
    select * into v_source_adjustment
      from public.inventory_adjustments
      where id = p_source_id and sale_id is not null
      for update;

    if not found then
      raise exception 'The selected replacement item could not be found.';
    end if;

    select coalesce(sum(quantity), 0)::integer into v_already_replaced
      from public.inventory_adjustments
      where source_adjustment_id = p_source_id;

    v_remaining_quantity := v_source_adjustment.quantity - v_already_replaced;
    v_root_sale_id := v_source_adjustment.sale_id;
    v_source_product_id := v_source_adjustment.product_id;
    v_source_product_name := v_source_adjustment.product_name;
    v_original_unit_price := coalesce(v_source_adjustment.replacement_unit_price, 0);
    v_source_adjustment_id := v_source_adjustment.id;
  else
    raise exception 'Choose an originally sold item or a previously replaced item.';
  end if;

  if v_remaining_quantity < 1 then
    raise exception 'This item has already been replaced.';
  end if;

  if p_quantity > v_remaining_quantity then
    raise exception 'Only % unit(s) from this sale remain eligible for replacement.', v_remaining_quantity;
  end if;

  select *
    into v_product
    from public.products
    where id = p_replacement_product_id
    for update;

  if not found then
    raise exception 'The selected replacement product could not be found.';
  end if;

  if v_product.stock < p_quantity then
    raise exception 'There is not enough stock for the selected replacement product.';
  end if;

  v_additional_amount := round(greatest(v_product.price - v_original_unit_price, 0) * p_quantity, 2);

  if v_additional_amount > 0 and (p_payment_method is null or p_payment_method not in ('cash', 'gcash')) then
    raise exception 'Select Cash or GCash for the additional payment.';
  end if;

  if p_payment_method is not null and p_payment_method not in ('cash', 'gcash') then
    raise exception 'Payment method must be Cash or GCash.';
  end if;

  v_payment_method := case when v_additional_amount > 0 then p_payment_method else null end;

  update public.products
    set stock = stock - p_quantity,
        status = case
          when stock - p_quantity <= 0 then 'Out of Stock'
          when stock - p_quantity <= 10 then 'Low Stock'
          else 'Active'
        end,
        updated_at = now()
    where id = p_replacement_product_id;

  insert into public.inventory_adjustments (
    product_id,
    product_name,
    quantity,
    reason,
    employee_id,
    employee_name,
    sale_id,
    source_adjustment_id,
    original_product_id,
    original_product_name,
    original_unit_price,
    replacement_unit_price,
    additional_amount,
    payment_method
  ) values (
    v_product.id,
    v_product.name,
    p_quantity,
    trim(p_reason),
    auth.uid(),
    coalesce(v_employee_name, 'Employee'),
    v_root_sale_id,
    v_source_adjustment_id,
    v_source_product_id,
    v_source_product_name,
    v_original_unit_price,
    v_product.price,
    v_additional_amount,
    v_payment_method
  )
  returning id into v_adjustment_id;

  if v_additional_amount > 0 then
    insert into public.sales (
      product_id,
      product_name,
      category,
      quantity,
      total_amount,
      employee_id,
      employee_name,
      sale_type,
      payment_method,
      created_at
    ) values (
      null,
      'Replacement price difference: ' || v_product.name,
      'Replacement charge',
      0,
      v_additional_amount,
      auth.uid(),
      coalesce(v_employee_name, 'Employee'),
      'replacement_charge',
      v_payment_method,
      now()
    );
  end if;

  return query select v_adjustment_id, v_additional_amount;
end;
$$;

revoke all on function public.complete_replacement(text, bigint, bigint, integer, text, text) from public, anon;
grant execute on function public.complete_replacement(text, bigint, bigint, integer, text, text) to authenticated;
