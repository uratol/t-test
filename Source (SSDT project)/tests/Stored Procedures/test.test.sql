CREATE procedure [tests].[test.test]
as
begin tran

	
	exec('create proc [tests].[temp-t-test.p1]
	as')

	exec('create proc [tests].[temp-t-test.p2]
	as')

	select test.assert_equals('View [test].[test] should return the tests (stored procedures in the schema [tests])'
		, (
			select *
			from (values
					( N'[tests].[temp-t-test.p1]', N'[temp-t-test].[p1]', N'temp-t-test', N'p1', NULL, N'temp-t-test.p1'),
					( N'[tests].[temp-t-test.p2]', N'[temp-t-test].[p2]', N'temp-t-test', N'p2', NULL, N'temp-t-test.p2')
				) as v(test_proc_full_name
					, tested_object_full_name
					, tested_object_schema_name
					, tested_object_name
					, tested_action
					, test_proc_name)
			for json path
			)
		, (
			select test_proc_full_name
				, tested_object_full_name
				, tested_object_schema_name
				, tested_object_name
				, tested_action
				, test_proc_name
			from test.test
			where tested_object_schema_name = 'temp-t-test'
			for json path
			)
	)

rollback