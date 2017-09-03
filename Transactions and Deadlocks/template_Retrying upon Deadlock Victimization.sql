/*
	Copyright (c) 2017 Ashok Gurumurthy

	Permission is hereby granted, free of charge, to any person obtaining a copy
	of this software and associated documentation files (the "Software"), to deal
	in the Software without restriction, including without limitation the rights
	to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
	copies of the Software, and to permit persons to whom the Software is
	furnished to do so, subject to the following conditions:

	The above copyright notice and this permission notice shall be included in all
	copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
	IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
	FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
	AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
	LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
	OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
	SOFTWARE.
*/

--------------------------------------------------------------------------------
/*
	Requires SQL Server 2012 or later (code for SQL Server 2008 is a separate
	file)
	
	This is boilerplate for running SQL statements as one transaction and
	retrying the SQL statements in the event that they become victims of a
	deadlock, up to a set maximum number of times. It is suggested, for clarity,
	that this boilerplate be made a stored procedure and the actual code to be
	run be put in a separate stored procedure that is called once from here, in
	the section labeled "Actual code goes here".

	This boilerplate is designed to be nestable. That is to say, the SQL wrapped
	in this boilerplate may itself use this boilerplate for subsections of code
	or may call stored procedures that do.

	Specify the parameters of code atomization and retrying of the transaction
	below.

	@MaxTries is the number of times (>= 1) to try to run the transaction. If the
	transaction fails the first time for a reason other than a deadlock, then
	there will be no re-trying, and the transaction will be rolled back. If the
	reason for failure is victimization by a deadlock with another transaction,
	then the code will be run up to @MaxTries-1 more times.

	@DelayString contains the time in hh:mm:ss format that must elapse following
	the rolling back of a failed run (due to deadlock victimization) and before
	retrying of the same transaction.

	IMPORTANT NOTE: If there was already an explicit transaction open when
	control entered this boilerplate, then there is no retrying if a deadlock is
	detected. This is because a deadlock puts the transaction in an invalid
	state, so that it is not possible to roll back to the savepoint that the
	template creates at the start. For the correct end result, the entire
	transaction, going back to the statement that incremented @@TRANCOUNT to 1,
	needs to be re-run. Responsibility for that falls on the caller of this
	boilerplate.

	In the event of an error other than a deadlock, the boilerplate rolls back
	the transaction back to the start of the boilerplate and re-throws the error
	to the caller.
*/

DECLARE @MaxTries int = 3;
DECLARE @DelayString varchar(8000) = '00:00:01';
--------------------------------------------------------------------------------



DECLARE @TranCounter int;
DECLARE @TranLabel varchar(max);
DECLARE @CurrentTry int = 0;
DECLARE @TransactionCommitSuccess bit = 0;
DECLARE @OriginalDeadlockPriority int;
DECLARE @CurrentDeadlockPriority int;
IF @MaxTries < 1 SET @MaxTries = 1;
WHILE @TransactionCommitSuccess = 0 AND @CurrentTry < @MaxTries
BEGIN;
	SET @TranCounter = @@TRANCOUNT;
	SET @TranLabel = REPLACE(NEWID(), '-', '');
	IF @TranCounter > 0
	BEGIN
		BEGIN TRANSACTION;
		SAVE TRANSACTION @TranLabel;
	END;
	ELSE
		BEGIN TRANSACTION @TranLabel;		

	BEGIN TRY;



		-------------------------------------
		-------------------------------------
		--	Actual code goes here
		-------------------------------------
		-------------------------------------



		SET @TransactionCommitSuccess = 1;
	END TRY
	BEGIN CATCH;
		SET @TransactionCommitSuccess = 0;
		SET @CurrentTry = @CurrentTry + 1;
		-----------------------------------------------------
		--- 1205 is the ERROR_NUMBER() for victimization by
		--- a deadlock. Retry only if there was no explicit
		--- transaction open at the start (@TranCounter = 0).
		--- That is because after a deadlock, rolling back to
		--- a savepoint is not possible; XACT_STATE() is -1.
		-----------------------------------------------------
		IF (@TranCounter = 0 AND @CurrentTry < @MaxTries AND (ERROR_NUMBER() = 1205 OR CHARINDEX('Error #1205', ERROR_MESSAGE()) > 0))
		BEGIN
			-----------------------------------------------------
			-- Deadlock detected. Retrying once after delay.
			-----------------------------------------------------
			ROLLBACK TRANSACTION;
			
			IF @CurrentTry = 1
			BEGIN
				SELECT @OriginalDeadlockPriority = [deadlock_priority] FROM sys.dm_exec_sessions WHERE session_id = @@SPID;
				SET @CurrentDeadlockPriority = @OriginalDeadlockPriority;
			END;
			
			IF @CurrentDeadlockPriority < 10
			BEGIN
				SET @CurrentDeadlockPriority = @CurrentDeadlockPriority + 1;
				SET DEADLOCK_PRIORITY @CurrentDeadlockPriority;
			END;

			WAITFOR DELAY @DelayString;
		END;
		ELSE IF @TranCounter = 0 OR XACT_STATE() != -1
		BEGIN
			IF (@@TRANCOUNT > @TranCounter)
				ROLLBACK TRANSACTION @TranLabel;
			WHILE (@@TRANCOUNT > @TranCounter AND XACT_STATE() = 1)
				COMMIT TRANSACTION;
			IF @CurrentDeadlockPriority != @OriginalDeadlockPriority
				SET DEADLOCK_PRIORITY @OriginalDeadlockPriority;
			THROW;
		END;
	END CATCH;
	IF @TransactionCommitSuccess = 1
	BEGIN
		WHILE @@TRANCOUNT > @TranCounter
			COMMIT TRANSACTION @TranLabel;

		IF @CurrentDeadlockPriority != @OriginalDeadlockPriority
			SET DEADLOCK_PRIORITY @OriginalDeadlockPriority;
	END;
END;