create function [test].[assert_error_number]
(
    @message nvarchar(max) -- Human-friendly description
  , @expected_number int   -- Number you expect ERROR_NUMBER() to return
)
returns int
as
begin
    declare @actual_number int = error_number(); -- inside CATCH

    if @actual_number is null
	       or @actual_number is distinct from @expected_number
        return test.throw_error(concat(
                                          @message
                                        , '. '
                                        , 'Error number '
                                        , @expected_number
                                        , ' expected. '
                                        , 'Got '
                                        , isnull(cast(@actual_number as nvarchar), '<null>')
                                      )
                               );

    return null; -- assertion passed
end