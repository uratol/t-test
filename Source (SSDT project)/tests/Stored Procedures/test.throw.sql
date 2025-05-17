CREATE proc [tests].[test.throw]
as
begin tran

begin try
	exec test.throw @message = 'Test exception!' -- nvarchar(max)
              , @proc_id = @@procid

    exec test.error
end try
begin catch

	select test.assert_error_like('Thrown exception should contain the message', 'Test exception!%')

	select test.assert_error_like('Thrown exception should contain the called procedure name separated by <Procedure:> tag'
		, concat('%'
			, '<Procedure:>' 
			, '%'
			, 
				quotename(object_schema_name(@@procid))
					, '.'
				, quotename(object_name(@@procid))
			, '%'
			)
		)

end catch

rollback