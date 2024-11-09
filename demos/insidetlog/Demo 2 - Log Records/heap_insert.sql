-- Run this and show it doesn't generate a logrec
BEGIN TRAN;

-- Show the logrecs

-- Now run an INSERT and COMMIT
INSERT INTO asimpletable VALUES (1);
COMMIT TRAN;

-- Show the logrecs
