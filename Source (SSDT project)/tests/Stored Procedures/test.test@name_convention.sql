create proc [tests].[test.test@name_convention]
as

select test.fail('Every tests should refer to the existing objects: ' + string_agg(test_proc_full_name, ', '))
from test.test as t
where object_id(t.tested_object_full_name) is null
	and (
		not exists(
			select * from sys.triggers as tr where tr.name = t.tested_object_name
		)
		or t.tested_object_schema_name is distinct from 'DDL trigger'
		)
having count(*) > 0