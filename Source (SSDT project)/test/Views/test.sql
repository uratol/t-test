CREATE view [test].[test]
as
select concat(quotename(s.name), '.', quotename(p.name))
	   as test_proc_full_name
	 , quotename(parsed.tested_object_schema_name) + '.' + quotename(parsed.tested_object_name)
	   as tested_object_full_name
	 , parsed.tested_object_schema_name
	 , parsed.tested_object_name
	 , iif(const.action_separator_index > 0, stuff(p.name, 1, const.action_separator_index, '')
	   , null
	   )	  as tested_action
	 , p.name as test_proc_name
	 , case 
			when parsed.tested_object_schema_name = 'private' then
				parsename(parsed.tested_object_name, 2)
			else parsed.tested_object_schema_name 
		end as tested_object_main_schema_name
from sys.procedures as p
	join sys.schemas as s
		on p.schema_id = s.schema_id
	outer apply (
		select charindex('.', p.name) as schema_separator_index
			 , charindex('@', p.name) as action_separator_index) as const
	outer apply (
		select iif(const.schema_separator_index > 0, left(p.name, const.schema_separator_index - 1), null) as tested_object_schema_name
			 , case when const.schema_separator_index > 0 then
			     substring(p.name
				   , const.schema_separator_index + 1
				   , len(p.name) - const.schema_separator_index
				   - iif(const.action_separator_index > 0
				   , len(p.name) - const.action_separator_index + 1
				   , 0)
				   )
			   end
			   as tested_object_name) as parsed
where s.name = 'tests'