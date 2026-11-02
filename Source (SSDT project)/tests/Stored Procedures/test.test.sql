CREATE procedure [tests].[test.test]
as
print N'Check discovery and metadata for two temporary test procs.'
print N'Expect: both procedures appear with the correct names.'
set nocount on
if @@trancount > 0 throw 51091, 'Discovery self-test requires no active transaction.', 1;

declare @expected nvarchar(max), @actual nvarchar(max), @assertion_result nvarchar(max)

-- Arrange
set @expected =
		N'[{"test_proc_full_name":"[tests].[temp-t-test.p1]","tested_object_full_name":"[temp-t-test].[p1]","tested_object_schema_name":"temp-t-test","tested_object_name":"p1","test_proc_name":"temp-t-test.p1"},'
		+ N'{"test_proc_full_name":"[tests].[temp-t-test.p2]","tested_object_full_name":"[temp-t-test].[p2]","tested_object_schema_name":"temp-t-test","tested_object_name":"p2","test_proc_name":"temp-t-test.p2"}]'
begin try
	begin tran
	exec(N'create proc [tests].[temp-t-test.p1] as return 0;')
	exec(N'create proc [tests].[temp-t-test.p2] as return 0;')

	-- Act
	set @actual = (
		select test_proc_full_name, tested_object_full_name,
			tested_object_schema_name, tested_object_name, tested_action, test_proc_name
		from test.test
		where tested_object_schema_name = 'temp-t-test'
		order by test_proc_name
		for json path
	)

	-- Assert
	set @assertion_result = test.assert_equals('Discovery must return both temporary procedures and their metadata'
		, @expected
		, @actual
		)

	rollback
end try
begin catch
	if @@trancount > 0 rollback;
	throw;
end catch