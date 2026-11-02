create proc [tests].[test.test@name_convention]
as
print N'Check test names and referenced database objects.'
print N'Expect: every registered test has a valid name.'

set nocount on

declare @message nvarchar(max)
	, @assertion_result int

-- Act
select @message = 'Schema-qualified tests must reference existing objects; conceptual tests must use object@action: ' + string_agg(convert(nvarchar(max), test_proc_full_name), ', ')
from test.test as t
where object_id(t.tested_object_full_name) is null
	and not (t.tested_object_schema_name is null
		and coalesce(len(t.tested_object_name), 0) > 0
		and coalesce(len(t.tested_action), 0) > 0)
having count(*) > 0

-- Assert
if @message is not null
	set @assertion_result = test.fail(@message)