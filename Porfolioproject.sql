-- Looking at breakdown of sales  for year 2004 

SELECT t1.orderDate, t1.orderNumber, productName, productLine, quantityOrdered, priceEach, buyPrice, city, country
FROM classicmodels.orders t1
INNER JOIN orderdetails t2
ON t1.orderNumber = t2.orderNumber
INNER JOIN products t3
ON t3.productCode = t2.productCode
INNER JOIN customers t4
ON t4.customerNumber = t1.customerNumber
WHERE year(orderDate) = 2004;


-- looking at breakdown of products purchased together.

with prod_sales as
(
SELECT  orderNumber, t1.productCode, productLine
FROM classicmodels.orderdetails t1
INNER JOIN products t2
ON t1.productCode = t2.productCode
)

Select distinct t1.orderNumber, t1.productLine as product_one, t2.productLine as product_two
from prod_sales t1
Left join prod_sales t2
on t1.orderNumber = t2.orderNumber and t1.productLine <> t2.productLine;


-- Looking at breakdown of customer sales with customer credit limit group

with sales as
(
select t1.orderNumber, t3.customerNumber, productCode, priceEach, quantityOrdered,
priceEach * quantityOrdered as sales_value , creditLimit
from classicmodels.orders t1
inner join orderdetails t2
on t1.orderNumber = t2.orderNumber
inner join customers t3
on t1.customerNumber = t3.customerNumber
)

select orderNumber, customerNumber, 
case when creditLimit < 75000 then 'a: Less than £75k'
when creditLimit between 75000 and 100000 then 'b: £75k - £100k'
when creditLimit between 100000 and 150000 then 'c: £100k - £150k'
when creditLimit > 150000 then 'd: Over £150k'
else 'other'
end as creditlimit_group,
sum(sales_value) as sales_value
from sales
group by orderNumber, customerNumber, creditLimit, creditlimit_group;


-- Looking at customer sales breakdown with difference in value from previous purchase

with sales_details as
(
select orderNumber, orderDate, customerNumber, sum(sales_value) as sales_value
from 
(select t1.orderNumber, orderDate, customerNumber, productCode, quantityOrdered * priceEach as sales_value
from orders t1
Inner Join orderdetails t2
on t1.orderNumber = t2.orderNumber) sales
group by orderNumber, OrderDate, customerNumber),

sales_query as
(select t1.*, customerName, row_number() over ( partition by customerName order by orderDate) as purchase_number,
lag(sales_value) over ( partition by customerName order by orderDate) as prev_sales_value
from sales_details t1
inner join customers t2
on t1.customerNumber = t2.customerNumber)

select *, sales_value - prev_sales_value as purchase_value_change
from sales_query
where prev_sales_value is not null;


-- Looking at breakdown of office sales by customer country.

with main_cte as
(
select t1.orderNumber, t2.productCode, quantityOrdered, priceEach, quantityOrdered * priceEach as sales_value, t3.city as customer_city, t3.country as customer_country,
t4.productLine,
t6.city as office_city,
t6.country as office_country
from orders t1
inner join orderdetails t2
on t1.orderNumber = t2.orderNumber
inner join customers t3
on t1.customerNumber = t3.customerNumber
inner join products t4
on t2.productCode = t4.productCode
inner join employees t5
on t3.salesRepEmployeeNumber = t5.employeeNumber
inner join offices t6
on t5.officeCode = t6.officeCode
)

select orderNumber, 
customer_city,
customer_country,
productLine,
office_city,
office_country,
sum(sales_value) as sales_value
from main_cte
group by orderNumber, 
customer_city,
customer_country,
productLine,
office_city,
office_country;


-- Looking at breakdown of customers affected by late shipping

Select *, 
date_add(shippedDate, interval 3 day) as latest_arrival,
case when date_add(shippedDate, interval 3 day) > requiredDate then 1 else 0  end as late_flag
from orders
where
(case when date_add(shippedDate, interval 3 day) > requiredDate then 1 else 0  end) = 1;


-- Looking at breakdown of customers who go over their credit limit

with cte_sales as
(select 
orderDate,
t1.customerNumber,
customerName,
t1.orderNumber,
productCode,
creditLimit,
quantityOrdered * priceEach as sales_value

from orders t1
inner join orderdetails t2
on t1.orderNumber = t2.orderNumber
inner join customers t3
on t1.customerNumber = t3.customerNumber
),

running_total_sales_cte as
(
select *, lead(orderdate) over( partition by customernumber order by orderdate) as next_order_date
from
	(
	select orderdate, ordernumber, customernumber, 
	customername, creditlimit, sum(sales_value) as sales_value
	from cte_sales
	group by 
	orderDate, orderNumber, customerNumber, 
	customerName, creditLimit
    )subquery
),

payment_cte as 
(
select *
from payments),

main_cte as
(
select t1.*,
sum(sales_value) over (partition by t1.customernumber order by orderdate) as running_total_sales,
sum(amount) over (partition by t1.customernumber order by orderdate) as running_total_payments
from running_total_sales_cte t1
left join payment_cte t2 
on t1.customernumber = t2.customernumber and t2.paymentdate between t1.orderdate and case when t1.next_order_date is null then current_date  else next_order_date end
)

select *, running_total_sales -  running_total_payments as money_owed,
creditlimit - (running_total_sales -  running_total_payments) as difference
from main_cte;

-- Creating view for PowerBI visualisation

Create or replace view sale_data_for_powebi as

select 
orderDate,
t1.orderNumber, productName, productLine, customerName, 
t3.country as customer_country, t7.country as office_country, 
buyPrice, priceEach, quantityOrdered,
quantityOrdered * priceEach as sales_value,
quantityOrdered * buyPrice as cost_of_sales
from orders t1
inner join orderdetails t2
on t1.orderNumber = t2.orderNumber
inner join customers t3
on t1.customerNumber = t3.customerNumber
inner join products t4
on t2.productCode = t4.productCode
inner join employees t6
on t3.salesRepEmployeeNumber = t6.employeeNumber
inner join offices t7
on t6.officeCode = t7.officeCode